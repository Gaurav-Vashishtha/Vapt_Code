class AddTotalPriceToAbandonedCarts < ActiveRecord::Migration[6.0]
  def change
    add_column :abandoned_carts, :total_price, :float
  end
end
