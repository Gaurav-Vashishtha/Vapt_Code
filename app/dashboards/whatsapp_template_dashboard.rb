require "administrate/base_dashboard"

class WhatsappTemplateDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    whatsapp_account: Field::BelongsTo,
    meta_template_id: Field::String,
    name: Field::String,
    language: Field::String,
    category: Field::String,
    status: Field::String,
    components: Field::Text,
    variable_mapping: Field::Text,
    url_button: Field::Text,
    header_media: Field::Text,
    event_type_key: Field::String,
    rejection_reason: Field::Text,
    last_synced_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    binding: Field::HasOne,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    whatsapp_account
    name
    language
    category
    status
    event_type_key
    last_synced_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    whatsapp_account
    meta_template_id
    name
    language
    category
    status
    event_type_key
    components
    variable_mapping
    url_button
    header_media
    rejection_reason
    binding
    last_synced_at
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    event_type_key
    status
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(t)
    "##{t.id} #{t.name} (#{t.language}, #{t.status})"
  end
end
