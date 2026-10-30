class AddAnalyticsIndexes < ActiveRecord::Migration[7.2]
  def change
    # Core index for most analytics queries - shop_id + created_at + order_amount filtering
    add_index :order_confirmations, [:shop_id, :created_at, :order_amount], 
              name: 'idx_order_confirmations_analytics_core'
    
    # Index for COD/Prepaid breakdown queries
    add_index :order_confirmations, [:shop_id, :created_at, :is_cod_order], 
              name: 'idx_order_confirmations_cod_breakdown'
    
    # Index for partial payment queries
    add_index :order_confirmations, [:shop_id, :created_at, :status, :order_amount], 
              name: 'idx_order_confirmations_partial_payment'
    
    # Index for status-based queries (verified, cod-prepaid)
    add_index :order_confirmations, [:shop_id, :status, :created_at], 
              name: 'idx_order_confirmations_status_analytics'
    
    # Abandoned cart analytics indexes
    add_index :abandoned_carts, [:shop_id, :created_at, :notes], 
              name: 'idx_abandoned_carts_analytics'
    
    add_index :abandoned_carts, [:shop_id, :created_at, :total_price], 
              name: 'idx_abandoned_carts_sales_analytics'
    
    # Twilio logs for communication analytics
    add_index :twilio_logs, [:shop_id, :created_at, :ver_type, :status], 
              name: 'idx_twilio_logs_communication_analytics'
    
    # Pre-order OTP analytics
    add_index :pre_order_otps, [:shop_id, :created_at, :status], 
              name: 'idx_pre_order_otps_analytics'
    
    # Abandoned cart communication analytics
    # add_index :abandoned_carts, [:shop_id, :created_at, :notif_type, :status], 
    #           name: 'idx_abandoned_carts_communication'
  end
end