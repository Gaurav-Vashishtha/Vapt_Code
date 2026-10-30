class BillingEvent < ApplicationRecord
  belongs_to :shop, optional: true

  EVENT_TYPES = %w[plan_activated upgraded downgraded cancelled charge_applied refund].freeze

  scope :in_period, ->(from, to) { where(occurred_at: from..to) }
  scope :of_type, ->(type) { where(event_type: type) }
end
