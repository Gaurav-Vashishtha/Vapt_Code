class AddExcludedShippingMethodsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :excluded_shipping_methods, :string, default:''
  end
end
