class AddShippingCostToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :shipping_cost, :decimal , :default => 1.0
  end
end
