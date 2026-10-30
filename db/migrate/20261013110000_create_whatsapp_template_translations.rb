# frozen_string_literal: true

# Translations of COD King's default-number MSG91 WhatsApp templates (one row per template and
# language, shared by every shop on the default number) and the default WhatsApp language per shop
# country used by onboarding.
class CreateWhatsappTemplateTranslations < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_template_translations do |t|
      t.string :template_name, null: false
      t.string :language, null: false
      t.string :category
      t.string :status, null: false, default: "not_started"
      t.jsonb :source_components, null: false, default: []
      t.jsonb :components, null: false, default: []
      t.string :drafted_by
      t.string :submitted_by
      t.text :rejection_reason
      t.jsonb :last_msg91_response, null: false, default: {}
      t.datetime :submitted_at
      t.datetime :approved_at
      t.datetime :last_synced_at
      t.timestamps
    end
    add_index :whatsapp_template_translations, %i[template_name language], unique: true,
              name: "index_wa_template_translations_on_name_and_language"
    add_index :whatsapp_template_translations, %i[language status],
              name: "index_wa_template_translations_on_language_and_status"

    create_table :whatsapp_country_languages do |t|
      t.string :country_code, null: false
      t.string :language, null: false
      t.timestamps
    end
    add_index :whatsapp_country_languages, :country_code, unique: true
  end
end
