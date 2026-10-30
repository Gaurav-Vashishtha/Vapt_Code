require "administrate/base_dashboard"

class SmsTemplateTypeConfigDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    key: Field::String.with_options(
      help: "Unique type key used by template manager, e.g. order_confirmation"
    ),
    display_name: Field::String.with_options(
      help: "Merchant-facing name shown in SMS Template Management"
    ),
    target_column: Field::String.with_options(
      help: "Existing settings column where approved template is applied"
    ),
    allowed_variables: Field::Text.with_options(
      help: "JSON array of variable names, e.g. [\"name\",\"number\",\"link\"]"
    ),
    max_variables: Field::Number.with_options(
      help: "Max variables allowed for this type (hard-capped to 3 in validation)"
    ),
    active: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    key
    display_name
    target_column
    max_variables
    active
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    key
    display_name
    target_column
    allowed_variables
    max_variables
    active
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    key
    display_name
    target_column
    allowed_variables
    max_variables
    active
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(resource)
    "#{resource.display_name} (#{resource.key})"
  end
end
