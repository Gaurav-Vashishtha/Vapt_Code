class AddPerformanceIndexes < ActiveRecord::Migration[7.2]
  def change
    # Critical indexes for the LEFT JOIN query optimization
    
    # 1. Composite index for abandon_cart_schedules JOIN condition
    add_index :abandon_cart_schedules, [:shop_id, :cart_id, :is_sheduled], 
              name: 'idx_acs_shop_cart_scheduled'
    
    # 2. Optimized index for abandon_cart_schedules lookup
    add_index :abandon_cart_schedules, [:shop_id, :is_sheduled], 
              name: 'idx_acs_shop_scheduled_lookup'
    
    # 3. Composite index for pre_order_otps main query conditions
    add_index :pre_order_otps, [:shop_id, :order_status, :created_at], 
              name: 'idx_pre_otps_shop_status_created'
    
    # 4. Index for device_id lookups (used in JOIN)
    add_index :pre_order_otps, [:device_id, :shop_id], 
              name: 'idx_pre_otps_device_shop'
    
    # 5. Index for cart_details filtering (exclude NULL values)
    add_index :pre_order_otps, [:shop_id, :order_status], 
              where: "cart_details IS NOT NULL",
              name: 'idx_pre_otps_with_cart_details'
    
    # 6. Improve existing abandoned_carts lookup for duplicate checking
    add_index :abandoned_carts, [:shop_id, :checkout_id, :notif_type, :scheduled_at], 
              name: 'idx_abandoned_carts_duplicate_check'
    
    # 7. Index for customer phone lookups
    add_index :customers, :phone, name: 'idx_customers_phone'
    
    # 8. Index for partial product mapping lookups
    add_index :partial_product_mappings, :partial_variant_id, 
              name: 'idx_partial_mappings_variant'
    
    # 9. Add covering index for the most common query pattern
    add_index :pre_order_otps, 
              [:shop_id, :order_status, :created_at, :device_id], 
              where: "cart_details IS NOT NULL AND order_status = 'AbandonedCheckout'",
              name: 'idx_pre_otps_covering_abandoned'
  end
end