class AddAnalyticsPartialIndexes < ActiveRecord::Migration[7.2]
  def change
    # Partial index for orders with valid amounts (excludes nil and empty strings)
    add_index :order_confirmations, [:shop_id, :created_at], 
              where: "order_amount IS NOT NULL AND order_amount != ''",
              name: 'idx_order_confirmations_valid_amounts'
    
    # Partial index for COD orders only
    add_index :order_confirmations, [:shop_id, :created_at, :order_amount], 
              where: "is_cod_order = true AND order_amount IS NOT NULL AND order_amount != ''",
              name: 'idx_order_confirmations_cod_only'
    
    # Partial index for prepaid orders only
    add_index :order_confirmations, [:shop_id, :created_at, :order_amount], 
              where: "is_cod_order = false AND order_amount IS NOT NULL AND order_amount != ''",
              name: 'idx_order_confirmations_prepaid_only'
    
    # Partial index for partial payment orders
    add_index :order_confirmations, [:shop_id, :created_at, :order_amount], 
              where: "status = 'COD-Partial-Payment-Received' AND order_amount IS NOT NULL AND order_amount != ''",
              name: 'idx_order_confirmations_partial_payments'
    
    # Partial index for recovered abandoned carts
    add_index :abandoned_carts, [:shop_id, :created_at, :total_price], 
              where: "LOWER(notes) = 'recovered'",
              name: 'idx_abandoned_carts_recovered'
  end
end