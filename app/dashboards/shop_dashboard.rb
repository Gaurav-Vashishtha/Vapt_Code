require "administrate/base_dashboard"

class ShopDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    setting: Field::HasOne.with_options(searchable: false),
    plan: Field::BelongsTo.with_options(searchable: false),
    order_confirmations: Field::HasMany.with_options(searchable: false),
    partial_rule_sets: Field::HasMany.with_options(searchable: false),
    abandoned_carts: Field::HasMany.with_options(searchable: false),
    id: Field::Number.with_options(searchable: false),
    shopify_domain: Field::String,
    shopify_token: Field::String.with_options(searchable: false),
    created_at: Field::DateTime.with_options(searchable: false),
    updated_at: Field::DateTime.with_options(searchable: false),
    customer_email: Field::String.with_options(searchable: false),
    owner_email: Field::String.with_options(searchable: false),
    owner_name: Field::String.with_options(searchable: false),
    primary_locale: Field::String.with_options(searchable: false),
    owner_phone: Field::String.with_options(searchable: false),
    country_name: Field::String.with_options(searchable: false),
    owner_timezone: Field::String.with_options(searchable: false),
    shop_owner: Field::String.with_options(searchable: false),
    charge_id: Field::String.with_options(searchable: false),
    sms_charge: Field::Number.with_options(decimals: 2),
    ivr_charge: Field::Number.with_options(decimals: 2),
    test_notif_count: Field::Number.with_options(searchable: false),
    country_code: Field::String.with_options(searchable: false),
    money_format: Field::String.with_options(searchable: false),
    currency: Field::String.with_options(searchable: false),
    max_orders: Field::Number.with_options(searchable: false),
    visible_plans: Field::String.with_options(searchable: false),
    reviewed: Field::Boolean.with_options(searchable: false),
    phone_pick_order: Field::String.with_options(searchable: false),
    cod_include_tags: Field::Text.with_options(searchable: false),
    cod_exclude_tags: Field::Text.with_options(searchable: false),
    primary_domain: Field::Text.with_options(searchable: true),
    risk_level: Field::Number.with_options(searchable: false),
    charge_multiplier: Field::Number.with_options(searchable: false),
    reminder_count: Field::Number.with_options(searchable: false),
    shop_created_date: Field::Text.with_options(searchable: false),
    relationship_manager: Field::Text.with_options(searchable: false),
    initial_customer_pull_completed: Field::DateTime.with_options(searchable: false),
    customer_count: Field::Number.with_options(searchable: false),
    shopify_plan: Field::Text.with_options(searchable: false),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id  
    charge_id
    risk_level
    setting
    plan
    country_code
    shopify_plan
    shop_created_date
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    reviewed
    risk_level
    setting
    plan
    order_confirmations
    partial_rule_sets
    abandoned_carts
    id
    shopify_domain
    shopify_token
    created_at
    updated_at
    customer_email
    owner_email
    owner_name
    primary_locale
    owner_phone
    country_name
    owner_timezone
    shop_owner
    charge_id
    sms_charge
    ivr_charge
    test_notif_count
    country_code
    money_format
    currency
    max_orders
    visible_plans
    shopify_plan
    phone_pick_order
    cod_include_tags
    cod_exclude_tags
    primary_domain
    charge_multiplier
    reminder_count
    shop_created_date
    relationship_manager
    initial_customer_pull_completed
    customer_count
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    reviewed
    risk_level
    plan
    shopify_domain
    shopify_token
    customer_email
    owner_email
    owner_name
    primary_locale
    owner_phone
    country_name
    owner_timezone
    shop_owner
    charge_id
    sms_charge
    ivr_charge
    test_notif_count
    country_code
    money_format
    currency
    max_orders
    visible_plans
    phone_pick_order
    cod_include_tags
    cod_exclude_tags
    primary_domain
    charge_multiplier
    reminder_count
    shop_created_date
    relationship_manager
    initial_customer_pull_completed
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

  # Overwrite this method to customize how shops are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(shop)
    "##{shop.id} - #{shop.shopify_domain}"
  end
end
