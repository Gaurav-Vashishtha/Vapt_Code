class AlterCustomerShopMapping < ActiveRecord::Migration[6.0]
  def change
    remove_column :customer_shop_mappings, :last_order_value
    add_column :customer_shop_mappings, :predicted_spend_tier, :string
    add_column :customer_shop_mappings, :lifetime_duration, :string
  end
end
