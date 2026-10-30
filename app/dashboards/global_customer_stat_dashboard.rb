# frozen_string_literal: true

require "administrate/base_dashboard"

class GlobalCustomerStatDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    customer_identity: Field::BelongsTo,
    total_orders: Field::Number,
    cod_orders: Field::Number,
    delivered: Field::Number,
    returned: Field::Number,
    rto: Field::Number,
    cancelled: Field::Number,
    refunded: Field::Number,
    last_order_at: Field::DateTime,
    extra: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    customer_identity
    total_orders
    rto
    returned
    last_order_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze

  FORM_ATTRIBUTES = %i[
    customer_identity
    total_orders
    cod_orders
    delivered
    returned
    rto
    cancelled
    refunded
    last_order_at
    extra
  ].freeze
end

