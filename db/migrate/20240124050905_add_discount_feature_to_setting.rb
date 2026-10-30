class AddDiscountFeatureToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :ac_whatsapp_discount, :string , default:''
    add_column :settings, :ac_whatsapp_discount_code, :string, default:''
    add_column :settings, :ac_whatsapp_discout_enabled, :boolean, default:false
  end
end
