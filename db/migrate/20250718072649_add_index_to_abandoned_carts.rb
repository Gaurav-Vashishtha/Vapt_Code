class AddIndexToAbandonedCarts < ActiveRecord::Migration[7.0]
  def change
    # Add composite index for faster lookups (not unique, so no expensive cleanup needed)
    add_index :abandoned_carts, 
              [:checkout_id, :notif_type, :scheduled_at], 
              name: 'idx_abandoned_carts_lookup'
  end
  # Rails automatically knows to remove_index for rollbacks
end