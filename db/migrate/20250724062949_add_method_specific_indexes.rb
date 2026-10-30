class AddMethodSpecificIndexes < ActiveRecord::Migration[7.2]
  def change
    # For average_order_value method - only valid amounts > 0
    add_index :order_confirmations, [:shop_id, :created_at], 
              where: "order_amount IS NOT NULL AND order_amount != '' AND order_amount::float > 0",
              name: 'idx_aov_calculations'
    
    # For order_type_breakdown method
    add_index :order_confirmations, [:shop_id, :created_at, :is_cod_order], 
              name: 'idx_order_type_breakdown'
    
    # For summary_metrics method - verified orders
    add_index :order_confirmations, [:shop_id, :created_at], 
              where: "status = 'COD-Verified'",
              name: 'idx_verified_orders'
    
    # For summary_metrics method - cod-prepaid orders
    add_index :order_confirmations, [:shop_id, :created_at], 
              where: "status = 'COD-Prepaid'",
              name: 'idx_cod_prepaid_orders'
  end
end