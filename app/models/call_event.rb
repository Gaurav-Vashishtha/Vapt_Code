# frozen_string_literal: true

class CallEvent < ApplicationRecord
  EVENT_TYPES = %w[
    outcome_logged comment_added reminder_set reminder_completed
    status_changed suppressed skipped
  ].freeze

  scope :for_domain, ->(domain) { where(shopify_domain: domain).order(occurred_at: :desc) }

  def self.record!(domain:, type:, agent: nil, shop_id: nil, payload: {})
    create!(
      shopify_domain: domain,
      event_type: type,
      agent_name: agent,
      shop_id: shop_id,
      payload: payload,
      occurred_at: Time.current
    )
  end
end
