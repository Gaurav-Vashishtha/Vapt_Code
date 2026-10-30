# frozen_string_literal: true

class WebhookEndpoint < ApplicationRecord
  belongs_to :shop
  has_many :inbound_webhook_events, dependent: :nullify

  encrypts :secret

  SIGNATURE_SCHEMES = %w[none shared_secret hmac_sha256].freeze

  validates :provider, presence: true
  validates :endpoint_token, presence: true, uniqueness: true
  validates :signature_scheme, inclusion: { in: SIGNATURE_SCHEMES }
  validates :shop_id, uniqueness: { scope: :provider, message: 'already has an endpoint for this provider' }
  validate  :provider_is_known
  validate  :secret_present_when_required

  before_validation :ensure_endpoint_token
  before_validation :ensure_secret

  scope :enabled, -> { where(enabled: true) }
  scope :for_provider, ->(provider) { where(provider: provider.to_s) }

  def ingest_path
    "/api/webhooks/#{provider}/#{endpoint_token}"
  end

  def ingest_url
    host = ENV['APP_HOST'].presence || ENV['HOST'].presence || 'app.codking.tech'
    "https://#{host.sub(%r{\Ahttps?://}, '')}#{ingest_path}"
  end

  def event_settings(event_name)
    definition = ::Webhooks::SourceRegistry.event(provider, event_name) || {}
    defaults = {
      'enabled'      => definition[:default_enabled] ? true : false,
      'amount_scale' => (definition[:default_amount_scale] || 1.0).to_f
    }
    defaults.merge(event_config[event_name.to_s] || {})
  end

  def event_enabled?(event_name)
    return false unless enabled?

    !!event_settings(event_name)['enabled']
  end

  # Shopflo quotes checkout_abandoned in rupees and added_to_cart_ui in paise,
  # so the multiplier has to stay per-event configuration.
  def amount_scale_for(event_name)
    scale = event_settings(event_name)['amount_scale'].to_f
    scale.positive? ? scale : 1.0
  end

  def update_event_setting!(event_name, attrs)
    merged = (event_config[event_name.to_s] || {}).merge(attrs.stringify_keys)
    update!(event_config: event_config.merge(event_name.to_s => merged))
  end

  def record_receipt!
    bump_stats!('received', last_received_at: Time.current)
  end

  def record_processed!
    bump_stats!('processed')
  end

  def record_skipped!
    bump_stats!('skipped')
  end

  def record_failure!
    bump_stats!('failed')
  end

  def counters
    {
      received:  stats['received'].to_i,
      processed: stats['processed'].to_i,
      skipped:   stats['skipped'].to_i,
      failed:    stats['failed'].to_i
    }
  end

  def rotate_secret!
    update!(secret: self.class.generate_secret)
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(24).tr('-_', 'ab')
  end

  def self.generate_secret
    "whsec_#{SecureRandom.hex(24)}"
  end

  private

  def bump_stats!(key, extra = {})
    current = (stats || {}).dup
    current[key] = current[key].to_i + 1
    update_columns({ stats: current, updated_at: Time.current }.merge(extra))
  rescue StandardError => e
    Rails.logger.warn("[webhook_endpoint] stats bump failed id=#{id}: #{e.class}: #{e.message}")
    nil
  end

  def ensure_endpoint_token
    return if endpoint_token.present?

    10.times do
      candidate = self.class.generate_token
      next if self.class.exists?(endpoint_token: candidate)

      self.endpoint_token = candidate
      break
    end
  end

  def ensure_secret
    self.secret = self.class.generate_secret if secret.blank?
  end

  def provider_is_known
    return if provider.blank?
    return if ::Webhooks::SourceRegistry.provider?(provider)

    errors.add(:provider, "#{provider} is not a known webhook provider")
  end

  def secret_present_when_required
    return if signature_scheme.to_s == 'none'
    return if secret.present?

    errors.add(:secret, 'is required unless signature_scheme is none')
  end
end
