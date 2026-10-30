require "administrate/base_dashboard"

class OrderConfirmationDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    shop: Field::BelongsTo.with_options(searchable: false),
    twilio_logs: Field::HasMany.with_options(searchable: false),
    id: Field::Number,
    order_id: Field::String,
    order_amount: Field::String.with_options(searchable: false),
    customer_name: Field::String,
    customer_number: Field::String.with_options(searchable: false),
    status: Field::String,
    confirmed_at: Field::DateTime.with_options(searchable: false),
    created_at: Field::DateTime.with_options(searchable: false),
    updated_at: Field::DateTime.with_options(searchable: false),
    otp_secret_key: Field::String.with_options(searchable: false),
    ivr_sid: Field::String.with_options(searchable: false),
    is_charged: Field::Boolean.with_options(searchable: false),
    is_otp_verified: Field::Boolean.with_options(searchable: false),
    country_code: Field::String.with_options(searchable: false),
    ver_type: Field::String.with_options(searchable: false),
    notif_count: Field::Number.with_options(searchable: false),
    order_status_url: Field::String.with_options(searchable: false),
    order_number: Field::String,
    customer_locale: Field::String.with_options(searchable: false),
    customer_id: Field::String.with_options(searchable: false),
    customer_email: Field::String.with_options(searchable: false),
    currency: Field::String.with_options(searchable: false),
    prepaid_link: Field::String.with_options(searchable: false),
    prepaid_status: Field::String.with_options(searchable: false),
    draft_payment_gateway: Field::String.with_options(searchable: false),
    draft_order_id: Field::String.with_options(searchable: false),
    draft_order_uuid: Field::String.with_options(searchable: false),
    persisted_otp: Field::String.with_options(searchable: false),
    is_retried: Field::Boolean.with_options(searchable: false),
    cod_fee: Field::Number.with_options(searchable: false),
    is_prepaid_charged: Field::Boolean.with_options(searchable: false),
    source_name: Field::String.with_options(searchable: false),
    digest: Field::String.with_options(searchable: false),
    payment_link_id: Field::String.with_options(searchable: false),
    phonepe_transaction_ids: Field::String.with_options(searchable: false),
    checkout_token: Field::String.with_options(searchable: false),
    is_cod_order: Field::Boolean.with_options(searchable: false),
    partial_payment_variants: Field::String.with_options(searchable: false),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    shop
    twilio_logs
    id
    order_id
    order_number
    order_amount
    customer_name
    status
    is_otp_verified
    payment_link_id
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    shop
    twilio_logs
    id
    order_id
    order_amount
    customer_name
    customer_number
    status
    is_otp_verified
    confirmed_at
    created_at
    updated_at
    otp_secret_key
    ivr_sid
    is_charged
    country_code
    ver_type
    notif_count
    order_status_url
    order_number
    customer_locale
    customer_id
    customer_email
    currency
    prepaid_link
    prepaid_status
    draft_payment_gateway
    draft_order_id
    draft_order_uuid
    persisted_otp
    is_retried
    cod_fee
    is_prepaid_charged
    source_name
    digest
    payment_link_id
    phonepe_transaction_ids
    checkout_token
    is_cod_order
    partial_payment_variants
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    order_id
    order_amount
    customer_name
    customer_number
    status
    is_otp_verified
    confirmed_at
    otp_secret_key
    ivr_sid
    is_charged
    country_code
    ver_type
    notif_count
    order_status_url
    order_number
    customer_locale
    customer_id
    shop
    customer_email
    currency
    prepaid_link
    prepaid_status
    draft_payment_gateway
    draft_order_id
    draft_order_uuid
    persisted_otp
    is_retried
    cod_fee
    is_prepaid_charged
    source_name
    digest
    payment_link_id
    phonepe_transaction_ids
    checkout_token
    is_cod_order
    partial_payment_variants
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how order confirmations are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(order_confirmation)
  #   "OrderConfirmation ##{order_confirmation.id}"
  # end
end
