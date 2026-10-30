class AddHideDeliveryMethodToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :hide_delivery_method, :string, default:''
  end
end
