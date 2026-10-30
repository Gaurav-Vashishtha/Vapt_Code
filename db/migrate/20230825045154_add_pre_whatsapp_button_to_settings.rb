class AddPreWhatsappButtonToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_whatsapp_button, :boolean, default: false
    add_column :settings, :pre_whatsapp_button_text, :text, default: 'Send Code to Whatsapp'
  end
end
