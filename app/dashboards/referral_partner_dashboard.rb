require "administrate/base_dashboard"

class ReferralPartnerDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account_type: Field::String,
    account_verified: Field::Boolean,
    account_verified_at: Field::DateTime,
    active: Field::Boolean,
    approved_shops: Field::HasMany,
    bank_account_name: Field::String,
    bank_account_number: Field::String,
    bank_ifsc_code: Field::String,
    bank_name: Field::String,
    email: Field::String,
    name: Field::String,
    notes: Field::Text,
    onetime_commission_rate: Field::String.with_options(searchable: false),
    password_digest: Field::String,
    payouts: Field::HasMany,
    paypal_email: Field::String,
    referral_earnings: Field::HasMany,
    referral_shops: Field::HasMany,
    subscription_commission_rate: Field::String.with_options(searchable: false),
    usage_commission_rate: Field::String.with_options(searchable: false),
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
    name
    email
    account_type
    account_verified
    account_verified_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account_type
    account_verified
    account_verified_at
    active
    approved_shops
    bank_account_name
    bank_account_number
    bank_ifsc_code
    bank_name
    email
    name
    notes
    onetime_commission_rate
    password_digest
    payouts
    paypal_email
    referral_earnings
    referral_shops
    subscription_commission_rate
    usage_commission_rate
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    account_type
    account_verified
    account_verified_at
    active
    approved_shops
    bank_account_name
    bank_account_number
    bank_ifsc_code
    bank_name
    email
    name
    notes
    onetime_commission_rate
    password_digest
    payouts
    paypal_email
    referral_earnings
    referral_shops
    subscription_commission_rate
    usage_commission_rate
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

  # Overwrite this method to customize how referral partners are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(referral_partner)
  #   "ReferralPartner ##{referral_partner.id}"
  # end
end
