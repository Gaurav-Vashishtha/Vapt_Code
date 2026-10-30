class AddWhatsappOrderConfirmationTemplateToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :whatsapp_order_confirmation_template, :string
  end
end
