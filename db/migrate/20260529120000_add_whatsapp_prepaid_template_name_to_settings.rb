class AddWhatsappPrepaidTemplateNameToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :whatsapp_prepaid_template_name, :string, default: 'order_tracking_new', null: false
  end
end
