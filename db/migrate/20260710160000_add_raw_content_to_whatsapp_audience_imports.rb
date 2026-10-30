# frozen_string_literal: true

class AddRawContentToWhatsappAudienceImports < ActiveRecord::Migration[7.2]
  def change
    add_column :whatsapp_audience_imports, :raw_content, :text
  end
end
