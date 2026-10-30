class AddIndexToPrepaidStatusOnOrderConfirmations < ActiveRecord::Migration[7.2]
  def change
    # Optimize queries filtering by created_at range and prepaid_status equality
    # Used in SystemDashboardController for partial payment orders and prepaid breakdown
    # Index order: prepaid_status (equality) first, created_at (range) second
    add_index :order_confirmations, [:prepaid_status, :created_at],
              name: 'idx_order_confirmations_prepaid_status_created_at'
  end
end
