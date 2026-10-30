# frozen_string_literal: true

require "administrate/base_dashboard"

module CodForm
  class FeatureGateDashboard < Administrate::BaseDashboard
    ATTRIBUTE_TYPES = {
      id: Field::Number,
      feature_key: Field::String,
      min_tier: Field::Select.with_options(searchable: false, collection: ::CodForm::FeatureGate::TIERS),
      enabled: Field::Boolean,
      description: Field::String,
      created_at: Field::DateTime,
      updated_at: Field::DateTime
    }.freeze

    COLLECTION_ATTRIBUTES = %i[
      id
      feature_key
      min_tier
      enabled
      description
    ].freeze

    SHOW_PAGE_ATTRIBUTES = %i[
      id
      feature_key
      min_tier
      enabled
      description
      created_at
      updated_at
    ].freeze

    # enabled = false switches the feature off for every shop.
    FORM_ATTRIBUTES = %i[
      feature_key
      min_tier
      enabled
      description
    ].freeze

    COLLECTION_FILTERS = {}.freeze

    def display_resource(feature_gate)
      "Feature gate #{feature_gate.feature_key}"
    end
  end
end
