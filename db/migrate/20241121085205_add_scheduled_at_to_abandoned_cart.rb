class AddScheduledAtToAbandonedCart < ActiveRecord::Migration[6.0]
  def change
    add_column :abandoned_carts, :scheduled_at, :datetime , default:nil
  end
end
