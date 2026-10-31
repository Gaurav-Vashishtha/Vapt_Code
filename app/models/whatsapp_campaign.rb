class WhatsappCampaign < ApplicationRecord
  belongs_to :shop
  belongs_to :whatsapp_account, optional: true
  belongs_to :whatsapp_template, optional: true
  belongs_to :whatsapp_audience_import, optional: true
  belongs_to :whatsapp_segment, optional: true
  has_many :recipients, class_name: 'WhatsappCampaignRecipient', dependent: :delete_all

  AUDIENCE_SOURCES = %w[abandoned_cart shopify_customer csv contacts segment].freeze
  STATUSES = %w[draft scheduled building testing sending paused retry_waiting completed cancelled failed].freeze

  validates :name, presence: true
  validates :audience_source, inclusion: { in: AUDIENCE_SOURCES }, allow_nil: true

  # retry_waiting campaigns park with scheduled_at = the earliest pending
  # retry, so the same scheduler tick that promotes scheduled campaigns also
  # resumes retries.
  scope :due, -> { where(status: %w[scheduled retry_waiting]).where('scheduled_at <= ?', Time.current) }
  scope :active_sending, -> { where(status: 'sending') }

  # Global cap on how many campaigns may be in `sending` at once, across all
  # shops. This bounds how many paced dispatch loops (and therefore how much of
  # the shared Sidekiq thread pool) campaign disbursement can occupy at a time.
  # Tune via ENV without a deploy; falls back to a conservative default.
  DEFAULT_MAX_CONCURRENT = 3

  def self.max_concurrent
    value = ENV.fetch("WHATSAPP_MAX_CONCURRENT_CAMPAIGNS", nil).to_i
    value.positive? ? value : DEFAULT_MAX_CONCURRENT
  end

  # Free slots right now (never negative). Promotion paths check this before
  # flipping a campaign to `sending`.
  def self.sending_slots_available
    [max_concurrent - active_sending.count, 0].max
  end

  def sending? = status == 'sending'
  def paused? = status == 'paused'
  def terminal? = %w[completed cancelled failed].include?(status)

  def retry_enabled? = Whatsapp::CampaignRetryPolicy.enabled?(self)
  def retry_delays_hours = Whatsapp::CampaignRetryPolicy.delays(self)
  def retry_pending_count = recipients.where(status: 'retry_pending').count
  def next_retry_at = recipients.where(status: 'retry_pending').minimum(:next_retry_at)
  # Cancelled campaigns can be relaunched: the audience is re-snapshotted and
  # already-sent recipients keep their status, so only pending ones get sent.
  def launchable? = %w[draft scheduled cancelled failed].include?(status) && whatsapp_template&.approved? && whatsapp_account&.ready_to_send?

  def deliverability
    base = sent_count.to_i + delivered_count.to_i + read_count.to_i
    {
      reach: audience_count.to_i,
      suppressed: suppressed_count.to_i,
      sent: base,
      delivered: delivered_count.to_i + read_count.to_i,
      read: read_count.to_i,
      failed: failed_count.to_i,
      replied: replied_count.to_i,
      delivery_rate: rate(delivered_count.to_i + read_count.to_i, base),
      read_rate: rate(read_count.to_i, base),
      fail_rate: rate(failed_count.to_i, base + failed_count.to_i)
    }
  end

  def progress_pct
    total = audience_count.to_i - suppressed_count.to_i
    return 0 if total <= 0
    done = sent_count.to_i + delivered_count.to_i + read_count.to_i + failed_count.to_i
    [(done * 100.0 / total).round, 100].min
  end

  def recompute_counts!
    grouped = recipients.group(:status).count
    update_columns(
      audience_count: recipients.count,
      suppressed_count: grouped['suppressed'].to_i,
      sent_count: grouped['sent'].to_i,
      delivered_count: grouped['delivered'].to_i,
      read_count: grouped['read'].to_i,
      failed_count: grouped['failed'].to_i,
      updated_at: Time.current
    )
  end

  # Runs inside BuildAudienceJob, where any error fails the whole campaign, so
  # an estimator problem falls back to the flat env rate instead of raising.
  def estimate_cost!
    reach = [audience_count.to_i - suppressed_count.to_i, 0].max
    estimate = estimator_result(reach)
    if estimate
      update_columns(estimated_cost: estimate[:amount].to_d.round(2), currency: estimate[:currency].presence || currency,
                     updated_at: Time.current)
    else
      rate = ENV.fetch("WHATSAPP_MARKETING_RATE", nil).to_f
      update_columns(estimated_cost: (reach * rate).round(2), updated_at: Time.current)
    end
  end

  private

  def estimator_result(reach)
    return nil unless defined?(::Whatsapp::CostEstimator)

    category = whatsapp_template&.category.to_s.upcase.presence || 'MARKETING'
    result = ::Whatsapp::CostEstimator.estimate(count: reach, category: category)
    result = result.to_h.symbolize_keys
    result[:amount].nil? ? nil : result
  rescue StandardError => e
    Rails.logger.warn("[WhatsappCampaign#estimate_cost!] campaign=#{id} #{e.class}: #{e.message}")
    nil
  end

  def rate(num, den)
    return 0.0 if den.to_i.zero?
    ((num.to_f / den) * 100).round(1)
  end
end
