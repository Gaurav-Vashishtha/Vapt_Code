require "administrate/base_dashboard"

class WhatsappAccountDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    shop: Field::BelongsTo,
    waba_id: Field::String,
    business_account_id: Field::String,
    phone_number_id: Field::String,
    display_phone_number: Field::String,
    verified_name: Field::String,
    quality_rating: Field::String,
    # `system_user_token` is `encrypts`'d — show it as plain text but treat
    # the rendered value as sensitive. Don't add it to FORM_ATTRIBUTES.
    system_user_token: Field::Text,
    token_expires_at: Field::DateTime,
    status: Field::String,
    registered_at: Field::DateTime,
    webhook_subscribed_at: Field::DateTime,
    last_synced_at: Field::DateTime,
    metadata: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    whatsapp_templates: Field::HasMany,
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    shop
    display_phone_number
    verified_name
    waba_id
    status
    registered_at
    last_synced_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    shop
    waba_id
    business_account_id
    phone_number_id
    display_phone_number
    verified_name
    quality_rating
    status
    registered_at
    token_expires_at
    webhook_subscribed_at
    last_synced_at
    metadata
    whatsapp_templates
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    status
    registered_at
    metadata
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(account)
    "##{account.id} #{account.display_phone_number} (#{account.status})"
  end
end
