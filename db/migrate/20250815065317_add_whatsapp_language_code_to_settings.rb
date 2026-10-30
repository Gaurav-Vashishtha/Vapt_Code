class AddWhatsappLanguageCodeToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :whatsapp_language_code, :string, default: 'en', null: false
  end
end