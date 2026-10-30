class AddAnalyticsPerformanceIndices < ActiveRecord::Migration[7.2]
  def change
    # ==========================================
    # ORDER_CONFIRMATIONS TABLE OPTIMIZATIONS
    # ==========================================
    
    # 1. Core daily analytics query optimization (NEW - different name)
    unless index_exists?(:order_confirmations, [:shop_id, :created_at, :status], name: 'idx_oc_daily_analytics')
      add_index :order_confirmations, 
                [:shop_id, :created_at, :status], 
                name: 'idx_oc_daily_analytics',
                where: "status != 'Test-Order'"
    end
    
    # 2. Order amount filtering optimization (NEW - different name)
    unless index_exists?(:order_confirmations, [:shop_id, :created_at, :order_amount], name: 'idx_oc_amount_analytics')
      add_index :order_confirmations, 
                [:shop_id, :created_at, :order_amount], 
                name: 'idx_oc_amount_analytics',
                where: "order_amount IS NOT NULL AND order_amount != ''"
    end
    
    # 3. COD/Prepaid breakdown optimization (SKIP - already exists)
    # idx_order_confirmations_cod_breakdown already exists from previous migration
    
    # 4. Partial payment queries optimization (SKIP - already exists)  
    # idx_order_confirmations_partial_payment already exists from previous migration
    
    # 5. Status-based analytics (NEW - different name)
    unless index_exists?(:order_confirmations, [:shop_id, :status, :created_at], name: 'idx_oc_status_summary')
      add_index :order_confirmations, 
                [:shop_id, :status, :created_at], 
                name: 'idx_oc_status_summary',
                where: "status IN ('COD-Verified', 'COD-Prepaid', 'COD-Partial-Payment-Received')"
    end

    # ==========================================
    # ABANDONED_CARTS TABLE OPTIMIZATIONS  
    # ==========================================
    
    # 6. Abandoned cart recovery analytics (SKIP - already exists)
    # idx_abandoned_carts_analytics already exists from previous migration
    
    # 7. Abandoned cart total price analytics (NEW - different name)
    unless index_exists?(:abandoned_carts, [:shop_id, :created_at, :total_price], name: 'idx_ac_price_recovery')
      add_index :abandoned_carts, 
                [:shop_id, :created_at, :total_price], 
                name: 'idx_ac_price_recovery',
                where: "total_price IS NOT NULL AND LOWER(notes) = 'recovered'"
    end

    # ==========================================
    # TWILIO_LOGS TABLE OPTIMIZATIONS
    # ==========================================
    
    # 8. Communication analytics optimization (SKIP - already exists)
    # idx_twilio_logs_communication_analytics already exists from previous migration
    
    # 9. Twilio status-based analytics (NEW - different name)
    unless index_exists?(:twilio_logs, [:shop_id, :created_at, :status], name: 'idx_twilio_status_analytics')
      add_index :twilio_logs, 
                [:shop_id, :created_at, :status], 
                name: 'idx_twilio_status_analytics'
    end

    # ==========================================
    # SHOPS TABLE OPTIMIZATION
    # ==========================================
    
    # 10. Currency lookup optimization for analytics (NEW)
    unless index_exists?(:shops, [:id, :currency], name: 'idx_shops_currency_lookup')
      add_index :shops, 
                [:id, :currency], 
                name: 'idx_shops_currency_lookup'
    end

    # ==========================================
    # SYSTEM_DASHBOARD OPTIMIZATIONS  
    # ==========================================
    
    # 11. System dashboard time-range queries (NEW)
    unless index_exists?(:shops, :created_at, name: 'idx_shops_created_at')
      add_index :shops, 
                :created_at, 
                name: 'idx_shops_created_at'
    end
    
    unless index_exists?(:uninstalled_shops, :created_at, name: 'idx_uninstalled_shops_created_at')
      add_index :uninstalled_shops, 
                :created_at, 
                name: 'idx_uninstalled_shops_created_at'
    end

    # ==========================================
    # PRE_ORDER_OTPS ADDITIONAL OPTIMIZATION
    # ==========================================
    
    # 12. Pre-order OTP analytics enhancement (NEW - different name)
    unless index_exists?(:pre_order_otps, [:verification_status, :created_at], name: 'idx_pre_otps_verification')
      add_index :pre_order_otps, 
                [:verification_status, :created_at], 
                name: 'idx_pre_otps_verification',
                where: "verification_status = 'VERIFIED'"
    end

    # ==========================================
    # ADDITIONAL NEW INDICES FOR MISSING GAPS
    # ==========================================
    
    # 13. Enhanced daily sales queries (NEW)
    unless index_exists?(:order_confirmations, [:shop_id, :is_cod_order, :created_at, :order_amount], name: 'idx_oc_daily_sales_enhanced')
      add_index :order_confirmations, 
                [:shop_id, :is_cod_order, :created_at, :order_amount], 
                name: 'idx_oc_daily_sales_enhanced',
                where: "status != 'Test-Order' AND order_amount IS NOT NULL"
    end
    
    # 14. AOV calculations optimized (NEW)
    unless index_exists?(:order_confirmations, [:shop_id, :created_at], name: 'idx_oc_aov_calc')
      add_index :order_confirmations, 
                [:shop_id, :created_at], 
                name: 'idx_oc_aov_calc',
                where: "status != 'Test-Order' AND order_amount IS NOT NULL AND order_amount != ''"
    end
  end
end