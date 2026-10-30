require "administrate/base_dashboard"

class WhatsappTemplateBindingDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    shop: Field::BelongsTo,
    whatsapp_template: Field::BelongsTo,
    event_type_key: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    shop
    event_type_key
    whatsapp_template
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    shop
    whatsapp_template
    event_type_key
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    event_type_key
    whatsapp_template
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(b)
    "##{b.id} #{b.event_type_key} → template #{b.whatsapp_template_id}"
  end
end
