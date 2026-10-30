require "administrate/base_dashboard"

class UninstalledShopDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    country: Field::String,
    email: Field::String,
    order_count: Field::String,
    owner_name: Field::String,
    phone: Field::String,
    shop_domain: Field::String,
    shop_id: Field::Number, 
    sms: Field::Boolean,
    notes: Field::String,
    confirmation_sms_enabled: Field::Boolean,
    cod_fee_enabled: Field::Boolean, 
    enable_pre_order_otp: Field::Boolean,
    abandoned_cart_enabled: Field::Boolean,
    prepaid_enabled: Field::Boolean,
    partial_payment_enabled: Field::Boolean,
    ac_whatsapp: Field::Boolean,
    bsp_integrated: Field::Boolean,
    cod_show_hide_enabled: Field::Boolean,
    shopify_created_on: Field::String,
    created_at: Field::DateTime,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    country
    email
    phone
    order_count
    shop_domain
    shopify_created_on
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    country
    email
    order_count
    owner_name
    phone
    notes
    shop_domain
    shop_id
    sms
    confirmation_sms_enabled
    cod_fee_enabled
    enable_pre_order_otp
    abandoned_cart_enabled
    prepaid_enabled
    partial_payment_enabled
    ac_whatsapp
    bsp_integrated
    cod_show_hide_enabled
    shopify_created_on
    created_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    country
    email
    order_count
    owner_name
    phone
    notes
    shop_domain
    shop_id
    sms
    confirmation_sms_enabled
    cod_fee_enabled
    enable_pre_order_otp
    abandoned_cart_enabled
    prepaid_enabled
    partial_payment_enabled
    ac_whatsapp
    bsp_integrated
    cod_show_hide_enabled
    shopify_created_on
    created_at
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

  # Overwrite this method to customize how uninstalled shops are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(uninstalled_shop)
  #   "UninstalledShop ##{uninstalled_shop.id}"
  # end
end
