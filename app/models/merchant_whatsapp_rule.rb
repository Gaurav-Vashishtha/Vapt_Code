# frozen_string_literal: true

class MerchantWhatsappRule < ApplicationRecord
  belongs_to :owner_whatsapp_template, optional: true
  has_many :scheduled_merchant_whatsapps, dependent: :destroy

  TRIGGER_TYPES = %w[scheduled event].freeze
  CATEGORIES = %w[onboarding aha recommendation digest winback].freeze
  DATE_RULE_TYPES = %w[days_after_installation hours_after_installation].freeze
  TARGETS = %w[shops uninstalled_shops].freeze

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :trigger_type, inclusion: { in: TRIGGER_TYPES }
  validates :target, inclusion: { in: TARGETS }

  scope :active, -> { where(active: true) }
  scope :scheduled, -> { active.where(trigger_type: "scheduled") }
  scope :for_event, ->(key) { active.where(trigger_type: "event", event_key: key.to_s) }

  def conditions_array
    return [] if conditions.blank?

    conditions.is_a?(Array) ? conditions : []
  end

  def scheduled?
    trigger_type == "scheduled"
  end

  def delay_offset
    return 0.seconds if date_rule_value.to_i.zero?

    date_rule_type == "hours_after_installation" ? date_rule_value.to_i.hours : date_rule_value.to_i.days
  end

  def date_rule_table_and_column
    col = date_rule_column.presence
    if col.to_s.include?(".")
      col.split(".", 2)
    else
      %w[shops created_at]
    end
  end
end
