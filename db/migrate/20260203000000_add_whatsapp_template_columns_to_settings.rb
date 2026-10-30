class AddWhatsappTemplateColumnsToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :whatsapp_first_purchase_template, :string
    add_column :settings, :whatsapp_abandoned_cart_template, :string
    add_column :settings, :whatsapp_fulfilment_template, :string
    add_column :settings, :whatsapp_cod_verification_template, :string
  end
end
