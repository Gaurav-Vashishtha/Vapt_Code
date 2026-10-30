# frozen_string_literal: true

require "administrate/base_dashboard"

module CodForm
  # Read-only (routes: index, show).
  class AdminAuditDashboard < Administrate::BaseDashboard
    ATTRIBUTE_TYPES = {
      id: Field::Number,
      auditable_type: Field::String,
      auditable_id: Field::Number,
      action: Field::String,
      changed_fields: JsonTextField,
      actor: Field::String,
      ip: Field::String,
      created_at: Field::DateTime
    }.freeze

    COLLECTION_ATTRIBUTES = %i[
      id
      auditable_type
      auditable_id
      action
      changed_fields
      actor
      created_at
    ].freeze

    SHOW_PAGE_ATTRIBUTES = %i[
      id
      auditable_type
      auditable_id
      action
      changed_fields
      actor
      ip
      created_at
    ].freeze

    FORM_ATTRIBUTES = [].freeze

    COLLECTION_FILTERS = {}.freeze

    def display_resource(admin_audit)
      "Audit ##{admin_audit.id}"
    end
  end
end
