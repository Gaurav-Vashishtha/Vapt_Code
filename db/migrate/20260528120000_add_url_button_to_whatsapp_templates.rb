class AddUrlButtonToWhatsappTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :whatsapp_templates, :url_button, :jsonb
  end
end
