class RenameCustomerShopData < ActiveRecord::Migration[6.0]
  def change
      rename_table :customer_shop_data, :customer_shop_mappings
  end
end
