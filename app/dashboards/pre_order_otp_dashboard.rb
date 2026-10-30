require "administrate/base_dashboard"

class PreOrderOtpDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    country_code: Field::String,
    device_id: Field::String,
    ip_address: Field::String,
    is_charged: Field::Boolean,
    notes: Field::String,
    otp: Field::String,
    phone: Field::String,
    shop: Field::BelongsTo,
    sid: Field::String,
    actual_charge_applied: Field::Number,
    status: Field::Boolean,
    shopify_order_ids: Field::String,
    cart_details: Field::Text,
    verification_status: Field::String,
    order_status: Field::String,
    ver_type: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    shop
    country_code
    phone
    ver_type
    verification_status
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    country_code
    device_id
    ip_address
    is_charged
    notes
    otp
    phone
    shop
    sid
    status
    actual_charge_applied

    
    shopify_order_ids
    cart_details
    order_status
    verification_status
    ver_type

    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    country_code
    device_id
    ip_address
    is_charged
    shop
    notes
    otp
    phone
    sid
    status
    actual_charge_applied

    shopify_order_ids
    cart_details
    order_status
    verification_status
    ver_type

  ].freeze

  COLLECTION_FILTERS = {}.freeze
end
