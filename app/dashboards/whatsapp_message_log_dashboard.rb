require "administrate/base_dashboard"

class WhatsappMessageLogDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    shop: Field::BelongsTo,
    whatsapp_account: Field::BelongsTo,
    whatsapp_template: Field::BelongsTo,
    event_type_key: Field::String,
    template_name: Field::String,
    recipient: Field::String,
    meta_message_id: Field::String,
    status: Field::String,
    error_code: Field::String,
    error_message: Field::Text,
    sent_at: Field::DateTime,
    delivered_at: Field::DateTime,
    read_at: Field::DateTime,
    failed_at: Field::DateTime,
    payload_snapshot: Field::Text,
    # Billing audit fields — written by PricingJobs::DynamicChargeJob.
    country_code: Field::String,
    is_charged: Field::Boolean,
    actual_charge_applied: Field::Number.with_options(decimals: 4),
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    shop
    event_type_key
    template_name
    recipient
    status
    country_code
    is_charged
    actual_charge_applied
    sent_at
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    shop
    whatsapp_account
    whatsapp_template
    event_type_key
    template_name
    recipient
    country_code
    status
    meta_message_id
    error_code
    error_message
    sent_at
    delivered_at
    read_at
    failed_at
    is_charged
    actual_charge_applied
    payload_snapshot
    created_at
    updated_at
  ].freeze

  # Logs are written by the system — admins should view, not edit. Form is left
  # near-empty so Administrate's edit page becomes effectively read-only.
  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(l)
    "##{l.id} #{l.event_type_key} → #{l.recipient} (#{l.status})"
  end
end
