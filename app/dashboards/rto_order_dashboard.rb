# frozen_string_literal: true

require "administrate/base_dashboard"

class RtoOrderDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    shop_domain: Field::BelongsTo,
    order_id: Field::String,
    order_number: Field::String,
    shopify_created_at: Field::DateTime,
    shopify_updated_at: Field::DateTime,
    last_fetched_at: Field::DateTime,
    processed_at: Field::DateTime,
    cancelled_at: Field::DateTime,
    closed_at: Field::DateTime,
    financial_status: Field::String,
    fulfillment_status: Field::String,
    is_cod: Field::Boolean,
    total_price: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    gateway: Field::String,
    zip: Field::String,
    city: Field::String,
    province: Field::String,
    country: Field::String,
    phone: Field::String,
    phone_normalized: Field::String,
    email: Field::String,
    email_normalized: Field::String,
    delivered_at: Field::DateTime,
    returned_at: Field::DateTime,
    rto_at: Field::DateTime,
    is_rto: Field::Boolean,
    is_returned: Field::Boolean,
    is_refunded: Field::Boolean,
    refund_amount: Field::Number.with_options(decimals: 2),
    outcome_status: Field::String,
    tags: Field::Text,
    raw_snapshot: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    shop_domain
    order_id
    shopify_created_at
    financial_status
    fulfillment_status
    zip
    outcome_status
  ].freeze

  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze

  FORM_ATTRIBUTES = %i[
    shop_domain
    order_id
    order_number
    shopify_created_at
    shopify_updated_at
    financial_status
    fulfillment_status
    is_cod
    total_price
    currency
    gateway
    zip
    city
    province
    country
    phone
    email
    outcome_status
    is_rto
    is_returned
    is_refunded
    refund_amount
    tags
  ].freeze
end

