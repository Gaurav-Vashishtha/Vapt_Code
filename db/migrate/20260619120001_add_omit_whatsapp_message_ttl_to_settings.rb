class AddOmitWhatsappMessageTtlToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :omit_whatsapp_message_ttl, :integer, default: 0, null: false
  end
end
