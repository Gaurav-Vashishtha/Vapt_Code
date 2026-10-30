class WhatsappMessageLog < ApplicationRecord
  # Owned by a Shop (merchant sends) OR a CustomBrandedClient (partner API
  # sends) — mirrors WhatsappAccount ownership; the send service copies both
  # columns from the account.
  belongs_to :shop, optional: true
  belongs_to :custom_branded_client, optional: true
  # nil once the sending number is disconnected — the log itself is kept.
  belongs_to :whatsapp_account, optional: true
  validate :exactly_one_owner
  belongs_to :whatsapp_template, optional: true
  # Customer replies correlated via Meta's context.id at webhook-time. Most
  # commonly quick-reply taps on a template button.
  has_many :inbound_messages,
           class_name: 'WhatsappInboundMessage',
           dependent: :nullify,
           inverse_of: :whatsapp_message_log

  enum status: {
    queued: 0,
    sent: 1,
    delivered: 2,
    read: 3,
    failed: 4,
    # Set by Whatsapp::ReattemptRecorder: waiting for a timed resend after a
    # retryable Meta refusal (e.g. 131049), or given up on. Neither is billed.
    retry_pending: 5,
    dropped: 6
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_event, ->(key) { where(event_type_key: key) if key.present? }
  scope :with_status, ->(s) { where(status: s) if s.present? }

  # Dedup helper used by the abandoned-cart reminder scheduler. A given
  # checkout token + stage_index should land in this table at most once.
  scope :already_sent_for_stage, ->(shop_id:, event_type_key:, source_external_id:, stage_index:) {
    where(
      shop_id: shop_id,
      event_type_key: event_type_key,
      source_external_id: source_external_id,
      stage_index: stage_index
    )
  }

  # Used by PricingJobs::DynamicChargeJob — bills only rows Meta has actually
  # accepted (queued = pre-HTTP; failed = Meta rejected). Mirrors the
  # `status: "SUCCESS"` filter the TwilioLog charging path uses.
  scope :chargeable, -> {
    where(is_charged: false).where(status: %i[sent delivered read])
  }

  before_validation :derive_country_code, on: :create
  after_commit :mirror_to_inbox, if: -> { saved_change_to_meta_message_id? && meta_message_id.present? && shop_id.present? }

  private

  def mirror_to_inbox
    ::Whatsapp::Inbox::OutboundMirror.call(self)
  rescue StandardError => e
    Rails.logger.error("[whatsapp_message_log] inbox mirror failed log=#{id}: #{e.class}: #{e.message}")
  end

  def exactly_one_owner
    if shop_id.present? && custom_branded_client_id.present?
      errors.add(:base, 'log cannot belong to both a shop and a custom branded client')
    elsif shop_id.blank? && custom_branded_client_id.blank?
      errors.add(:base, 'log must belong to a shop or a custom branded client')
    end
  end

  # Phonelib expects an E.164-style number to detect country. Recipient is
  # stored as the caller passed it (sometimes digits-only, sometimes with +).
  # Strip non-digits and prepend + before parsing. Country billing falls back
  # to whatever was already on the row if parsing fails.
  def derive_country_code
    return if country_code.present?
    return if recipient.blank?
    digits = recipient.to_s.gsub(/\D/, '')
    return if digits.blank?
    parsed = Phonelib.parse("+#{digits}")
    self.country_code = parsed.country if parsed.valid? && parsed.country.present?
  rescue StandardError => e
    Rails.logger.warn("[whatsapp_message_log] country_code derive failed: #{e.message}")
  end

  public

  # Promote status only forward — Meta sometimes sends out-of-order webhooks
  # (e.g. `delivered` arrives after `read`). Never regress to an earlier state.
  STATUS_ORDER = { 'queued' => 0, 'sent' => 1, 'delivered' => 2, 'read' => 3, 'failed' => 4,
                   'retry_pending' => 4, 'dropped' => 4 }.freeze

  def advance_status!(new_status, at:)
    return if new_status.blank?
    return unless STATUS_ORDER.key?(new_status.to_s)

    # `failed` is terminal in either direction — always honour it.
    if new_status.to_s == 'failed' || STATUS_ORDER[new_status.to_s] > STATUS_ORDER[status.to_s]
      attrs = { status: new_status }
      attrs[:"#{new_status}_at"] = at if respond_to?("#{new_status}_at=")
      update!(attrs)
    end
  end
end
