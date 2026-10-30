class AddCustomerCountToUninstalledShops < ActiveRecord::Migration[7.2]
  def change
    add_column :uninstalled_shops, :customer_count, :integer
  end
end
