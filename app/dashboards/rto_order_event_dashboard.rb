# frozen_string_literal: true

require "administrate/base_dashboard"

class RtoOrderEventDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    shop_domain: Field::BelongsTo,
    order_id: Field::String,
    event_type: Field::String,
    occurred_at: Field::DateTime,
    source: Field::String,
    webhook_id: Field::String,
    payload_json: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    shop_domain
    order_id
    event_type
    occurred_at
    source
  ].freeze

  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze

  FORM_ATTRIBUTES = %i[
    shop_domain
    order_id
    event_type
    occurred_at
    source
    webhook_id
    payload_json
  ].freeze
end

