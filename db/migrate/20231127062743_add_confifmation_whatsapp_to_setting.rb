class AddConfifmationWhatsappToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :confirmation_whatsapp, :boolean, default:false
    add_column :settings, :fulfilment_whatsapp, :boolean, default:false
  end
end
