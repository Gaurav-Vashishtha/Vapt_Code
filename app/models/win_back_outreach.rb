class WinBackOutreach < ApplicationRecord
  belongs_to :shop, optional: true

  TRIGGERS = %w[at_risk just_churned].freeze
  STATUSES = %w[pending sent skipped failed].freeze

  scope :recent_for, ->(shop_id, trigger, days = 14) {
    where(shop_id: shop_id, trigger: trigger).where('created_at >= ?', days.days.ago)
  }
end
