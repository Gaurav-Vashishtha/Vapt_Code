require "administrate/base_dashboard"

class AbandonedCartDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    shop: Field::BelongsTo,
    id: Field::Number,
    checkout_id: Field::String,
    url: Field::String,
    status: Field::String,
    notes: Field::String,
    sid: Field::String,
    phone: Field::String,
    country_code: Field::String,
    shopify_created_at: Field::String,
    notif_type: Field::String,
    name: Field::String,
    featured_image: Field::String,
    total_price: Field::Number,
    is_charged: Field::Boolean,
    scheduled_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    shop
    id
    checkout_id
    scheduled_at
    notif_type
    url
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    shop
    id
    checkout_id
    url
    status
    notes
    sid
    phone
    country_code
    shopify_created_at
    notif_type
    name
    featured_image
    total_price
    is_charged
    scheduled_at
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    shop
    checkout_id
    url
    status
    notes
    sid
    phone
    name
    country_code
    featured_image
    shopify_created_at
    notif_type
    total_price
    is_charged
    scheduled_at
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

  # Overwrite this method to customize how abandoned carts are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(abandoned_cart)
  #   "AbandonedCart ##{abandoned_cart.id}"
  # end
end
