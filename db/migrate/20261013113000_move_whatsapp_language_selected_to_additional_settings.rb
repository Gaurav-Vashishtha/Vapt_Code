# frozen_string_literal: true

# The "merchant picked their WhatsApp language" flag lives in additional_settings, not settings.
# Databases that already ran an earlier draft of CreateWhatsappTemplateTranslations have it on
# settings; this drops that copy and adds the additional_settings one.
class MoveWhatsappLanguageSelectedToAdditionalSettings < ActiveRecord::Migration[7.2]
  def up
    remove_column :settings, :whatsapp_language_selected if column_exists?(:settings, :whatsapp_language_selected)
    unless column_exists?(:additional_settings, :whatsapp_language_selected)
      add_column :additional_settings, :whatsapp_language_selected, :boolean, null: false, default: false
    end
  end

  def down
    remove_column :additional_settings, :whatsapp_language_selected if column_exists?(:additional_settings, :whatsapp_language_selected)
  end
end
