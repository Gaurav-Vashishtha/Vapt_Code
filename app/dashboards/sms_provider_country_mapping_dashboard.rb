require "administrate/base_dashboard"

class SmsProviderCountryMappingDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    provider: Field::String.with_options(
      help: "Full service class name (e.g., SmsServices::MoviderSmsService, SmsServices::ThaiSmsService). Required format: SmsServices::[Name]SmsService or WhatsappServices::[Name]WhatsappService"
    ),
    supported_countries: Field::Text.with_options(
      help: "Comma-separated country codes (e.g., TH,PH,ID,IN). Use ISO 2-letter country codes (uppercase)."
    ),
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
    provider
    supported_countries
    created_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    provider
    supported_countries
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    provider
    supported_countries
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

  # Overwrite this method to customize how sms provider country mappings are displayed
  # across all pages of the admin dashboard.
  def display_resource(sms_provider_country_mapping)
    provider_name = sms_provider_country_mapping.provider.split('::').last.gsub('SmsService', '').gsub('Service', '')
    countries = sms_provider_country_mapping.supported_countries.presence || "No countries"
    "#{provider_name} (#{countries})"
  end
end

