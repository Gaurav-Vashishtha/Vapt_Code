require "administrate/base_dashboard"

class TwilioLogDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    order_confirmation: Field::BelongsTo,
    shop: Field::BelongsTo,
    id: Field::Number,
    sid: Field::String,
    ver_type: Field::String,
    country_code: Field::String,
    customer_number: Field::String,
    is_charged: Field::Boolean,
    status: Field::String,
    num_segment: Field::Number,
    actual_charge_applied: Field::Number, 
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    order_confirmation
    id
    sid
    ver_type
    status
    actual_charge_applied
    country_code
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    order_confirmation
    shop
    id
    sid
    ver_type
    country_code
    customer_number
    is_charged
    num_segment
    actual_charge_applied
    status
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    order_confirmation
    shop
    sid
    ver_type
    country_code
    customer_number
    actual_charge_applied
    is_charged
    status
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

  # Overwrite this method to customize how twilio logs are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(twilio_log)
  #   "TwilioLog ##{twilio_log.id}"
  # end
end
