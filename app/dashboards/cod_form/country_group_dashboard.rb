# frozen_string_literal: true

require "administrate/base_dashboard"

module CodForm
  class CountryGroupDashboard < Administrate::BaseDashboard
    ATTRIBUTE_TYPES = {
      id: Field::Number,
      name: Field::String,
      country_codes: JsonTextField.with_options(rows: 3),
      position: Field::Number,
      active: Field::Boolean,
      created_at: Field::DateTime,
      updated_at: Field::DateTime
    }.freeze

    COLLECTION_ATTRIBUTES = %i[
      id
      name
      country_codes
      position
      active
    ].freeze

    SHOW_PAGE_ATTRIBUTES = %i[
      id
      name
      country_codes
      position
      active
      created_at
      updated_at
    ].freeze

    # country_codes: JSON array of ISO2 codes, e.g. ["HU", "CO"].
    FORM_ATTRIBUTES = %i[
      name
      country_codes
      position
      active
    ].freeze

    COLLECTION_FILTERS = {}.freeze

    def display_resource(country_group)
      "Country group ##{country_group.id} #{country_group.name}"
    end
  end
end
