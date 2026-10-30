require "administrate/base_dashboard"

class PayoutDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    completed_at: Field::DateTime,
    created_by: Field::String,
    currency: Field::String,
    earnings_from_date: Field::Date,
    earnings_to_date: Field::Date,
    notes: Field::Text,
    payment_details: Field::Text,
    payment_method: Field::String,
    payout_date: Field::Date,
    payout_earnings: Field::HasMany,
    processed_at: Field::DateTime,
    referral_earnings: Field::HasMany,
    referral_partner: Field::BelongsTo,
    status: Field::String,
    total_amount: Field::String.with_options(searchable: false),
    transaction_reference: Field::String,
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
    completed_at
    created_by
    currency
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    completed_at
    created_by
    currency
    earnings_from_date
    earnings_to_date
    notes
    payment_details
    payment_method
    payout_date
    payout_earnings
    processed_at
    referral_earnings
    referral_partner
    status
    total_amount
    transaction_reference
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    completed_at
    created_by
    currency
    earnings_from_date
    earnings_to_date
    notes
    payment_details
    payment_method
    payout_date
    payout_earnings
    processed_at
    referral_earnings
    referral_partner
    status
    total_amount
    transaction_reference
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

  # Overwrite this method to customize how payouts are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(payout)
  #   "Payout ##{payout.id}"
  # end
end
