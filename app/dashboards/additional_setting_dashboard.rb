require "administrate/base_dashboard"

class AdditionalSettingDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    # A plain number box on purpose: a Shop select would load every shop in production.
    shop_id: Field::Number.with_options(
      searchable: true,
      help: "The shop's ID (Shops → id). One row per shop."
    ),
    shop_domain: Field::String.with_options(searchable: false),
    third_party_payment_method_rules: JsonTextField.with_options(rows: 4),
    pre_order_otp_draft_orders: Field::Boolean.with_options(
      help: "Create a Shopify draft order for each abandoned (OTP-verified) pre-order OTP cart."
    ),
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    shop_id
    shop_domain
    third_party_payment_method_rules
    pre_order_otp_draft_orders
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    shop_id
    shop_domain
    third_party_payment_method_rules
    pre_order_otp_draft_orders
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    shop_id
    third_party_payment_method_rules
    pre_order_otp_draft_orders
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(additional_setting)
    "Additional settings ##{additional_setting.id} (shop #{additional_setting.shop_id})"
  end
end
