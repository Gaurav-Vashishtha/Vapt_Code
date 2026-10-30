require "administrate/base_dashboard"

class PartialRuleSetDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    amount: Field::String.with_options(searchable: false),
    amount_type: Field::String,
    is_all: Field::Boolean,
    product_scope: Field::String,
    is_enabled: Field::Boolean,
    product_ids: Field::String,
    rule_name: Field::String,
    is_cart_rule: Field::Boolean,
    discount_code: Field::String,
    discount_value: Field::Number,
    discount_type: Field::String,
    amount_to_show: Field::String,
    sub_heading: Field::String,
    custom_save_text: Field::String,
    shipping_charge_text: Field::String,
    min_cart_range: Field::Number,
    max_cart_range: Field::Number,
    checkout_cod_only: Field::Boolean,
    shop: Field::BelongsTo,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    amount
    amount_type
    product_scope
    is_all
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    amount
    amount_type
    is_all
    product_scope
    is_enabled
    product_ids
    rule_name
    shop
    is_cart_rule
    discount_code
    discount_value
    discount_type
    amount_to_show
    sub_heading
    custom_save_text
    shipping_charge_text
    min_cart_range
    max_cart_range
    checkout_cod_only
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    amount
    amount_type
    is_all
    is_enabled
    product_ids
    rule_name
    is_cart_rule
    discount_code
    discount_value
    discount_type
    amount_to_show
    sub_heading
    custom_save_text
    shipping_charge_text
    min_cart_range
    max_cart_range
    checkout_cod_only
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

  # Overwrite this method to customize how partial rule sets are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(partial_rule_set)
  #   "PartialRuleSet ##{partial_rule_set.id}"
  # end
end
