class AddIndexToAbandonedCartsCheckoutId < ActiveRecord::Migration[7.2]
  def change
        add_index :abandoned_carts, :checkout_id
  end
end
