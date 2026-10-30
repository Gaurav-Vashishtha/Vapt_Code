# frozen_string_literal: true

class WhatsappOrderAttribution < ApplicationRecord
  TYPES = %w[order cod_to_prepaid].freeze

  belongs_to :shop
  belongs_to :whatsapp_campaign, optional: true
  belongs_to :whatsapp_message_log, optional: true
  belongs_to :order_confirmation, optional: true

  validates :order_id, :ordered_at, :touch_at, :phone_last10, :event_type_key, presence: true
  validates :attribution_type, inclusion: { in: TYPES }

  scope :orders, -> { where(attribution_type: 'order') }
  scope :conversions, -> { where(attribution_type: 'cod_to_prepaid') }
end
