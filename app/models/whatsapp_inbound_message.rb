class WhatsappInboundMessage < ApplicationRecord
  # Owned by a Shop OR a CustomBrandedClient — mirrors WhatsappAccount
  # ownership; the webhook router copies both columns from the account.
  belongs_to :shop, optional: true
  belongs_to :custom_branded_client, optional: true
  belongs_to :whatsapp_account, optional: true # nil once the number is disconnected
  belongs_to :whatsapp_message_log, optional: true

  validates :meta_message_id, presence: true, uniqueness: true
  validates :from_phone, :kind, :received_at, presence: true
  validate :exactly_one_owner

  scope :recent, -> { order(received_at: :desc) }

  # Quick-reply taps and interactive replies — what most merchants care about.
  # Free-text inbound messages still get stored (kind='text') but are excluded
  # here so the default Activity "Replies" view doesn't get noisy.
  scope :button_taps, -> { where(kind: %w[button interactive]) }

  SOURCES = %w[campaign notification direct].freeze

  scope :from_source, lambda { |source|
    case source.to_s
    when 'campaign'
      joins(:whatsapp_message_log).where.not(whatsapp_message_logs: { whatsapp_campaign_id: nil })
    when 'notification'
      joins(:whatsapp_message_log).where(whatsapp_message_logs: { whatsapp_campaign_id: nil })
    when 'direct'
      where(whatsapp_message_log_id: nil)
    else
      all
    end
  }

  scope :matching, lambda { |q|
    term = q.to_s.strip
    next all if term.blank?

    like = "%#{sanitize_sql_like(term)}%"
    digits = term.gsub(/\D/, '')
    if digits.length >= 4
      where('whatsapp_inbound_messages.display_text ILIKE :like OR whatsapp_inbound_messages.from_phone LIKE :digits',
            like: like, digits: "%#{digits}%")
    else
      where('whatsapp_inbound_messages.display_text ILIKE :like', like: like)
    end
  }

  private

  def exactly_one_owner
    if shop_id.present? && custom_branded_client_id.present?
      errors.add(:base, 'inbound cannot belong to both a shop and a custom branded client')
    elsif shop_id.blank? && custom_branded_client_id.blank?
      errors.add(:base, 'inbound must belong to a shop or a custom branded client')
    end
  end
end
