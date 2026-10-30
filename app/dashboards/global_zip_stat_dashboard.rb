# frozen_string_literal: true

require "administrate/base_dashboard"

class GlobalZipStatDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    zip: Field::String,
    country: Field::String,
    total_orders: Field::Number,
    cod_orders: Field::Number,
    delivered: Field::Number,
    returned: Field::Number,
    rto: Field::Number,
    cancelled: Field::Number,
    refunded: Field::Number,
    last_order_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    country
    zip
    total_orders
    rto
    returned
    last_order_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze

  FORM_ATTRIBUTES = %i[
    zip
    country
    total_orders
    cod_orders
    delivered
    returned
    rto
    cancelled
    refunded
    last_order_at
  ].freeze
end

