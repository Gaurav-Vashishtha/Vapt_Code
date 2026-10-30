# frozen_string_literal: true

class AddComponentsToOwnerWhatsappTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :owner_whatsapp_templates, :components, :jsonb, default: []
    add_column :owner_whatsapp_templates, :footer_text, :text
  end
end
