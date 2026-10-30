class AddMaxOrdersToShops < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :max_orders, :integer
  end
end
