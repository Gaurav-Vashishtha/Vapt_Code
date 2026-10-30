class AddDeliveryCustomizationToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :delivery_customization_id, :string, default:''
  end
end
