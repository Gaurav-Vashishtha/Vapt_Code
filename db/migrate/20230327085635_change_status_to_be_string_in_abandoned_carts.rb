class ChangeStatusToBeStringInAbandonedCarts < ActiveRecord::Migration[6.0]
  def change
      change_column :abandoned_carts, :status, :string
  end
end
