class AddHideShippingMethodToSetting < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :hide_shipping_method, :boolean, default:false
  end
end
