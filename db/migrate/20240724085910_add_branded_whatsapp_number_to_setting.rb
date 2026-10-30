class AddBrandedWhatsappNumberToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :branded_whatsapp_number, :string , default:''
  end
end
