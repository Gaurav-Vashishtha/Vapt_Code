# frozen_string_literal: true

require "administrate/base_dashboard"

class CustomerIdentityDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    phone_normalized: Field::String,
    email_normalized: Field::String,
    global_customer_stat: Field::HasOne,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    phone_normalized
    email_normalized
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze

  FORM_ATTRIBUTES = %i[
    phone_normalized
    email_normalized
  ].freeze
end

