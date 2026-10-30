class AddCustomerCreateNotifToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :first_purchase_whatsapp_enabled, :boolean , default:false
    add_column :settings, :first_purchase_schedule, :string , default:''
    add_column :settings, :first_purchase_discount_code, :string , default:''
    add_column :settings, :first_purchase_discount_off, :string , default:''
  end
end
