class SystemDashboardController < ApplicationController
    def index
      @time_range = params[:time_range] || '24_hours'
      @start_time = calculate_start_time(@time_range)
      
      # Calculate metrics based on time range
      @total_shops = Shop.count
      @shops_in_range = Shop.where('created_at >= ?', @start_time).count
      
      @total_uninstalled_shops = UninstalledShop.count
      @uninstalled_shops_in_range = UninstalledShop.where('created_at >= ?', @start_time).count
      
      @total_order_confirmations = OrderConfirmation.count
      @order_confirmations_in_range = OrderConfirmation.where('created_at >= ?', @start_time).count
      
      @total_abandoned_carts = AbandonedCart.count
      @abandoned_carts_in_range = AbandonedCart.where('created_at >= ?', @start_time).count
      
      @total_customers = Customer.count
      @customers_in_range = Customer.where('created_at >= ?', @start_time).count
      
      # Calculate percentages and trends
      @shops_growth = calculate_growth_percentage(@shops_in_range, @total_shops)
      @uninstall_rate = calculate_percentage(@total_uninstalled_shops, @total_shops)
      
      # Additional metrics - using proper association name
      @active_shops = Shop.joins("LEFT JOIN settings ON shops.id = settings.shop_id").where("settings.status = ?", true).count
      @shops_with_cod_enabled = Shop.joins("LEFT JOIN settings ON shops.id = settings.shop_id").where("settings.cod_fee_enabled = ?", true).count
      @shops_with_prepaid_enabled = Shop.joins("LEFT JOIN settings ON shops.id = settings.shop_id").where("settings.prepaid_enabled = ?", true).count
      
      # Calculate adoption percentages
      @cod_adoption_percentage = calculate_percentage(@shops_with_cod_enabled, @total_shops)
      @prepaid_adoption_percentage = calculate_percentage(@shops_with_prepaid_enabled, @total_shops)
      
      # NEW ENHANCED METRICS
      
      # 1. Pre Order OTP Verification Status
      @total_pre_order_otps = PreOrderOtp.otp_sends.count
      @pre_order_otps_in_range = PreOrderOtp.otp_sends.where('created_at >= ?', @start_time).count
      @otp_verified = PreOrderOtp.otp_sends.where(verification_status: 'VERIFIED').count
      @otp_verified_in_range = PreOrderOtp.otp_sends.where('created_at >= ?', @start_time).where(verification_status: 'VERIFIED').count
      @otp_verification_rate = calculate_percentage(@otp_verified, @total_pre_order_otps)
      
      # 2. Twilio Logs Breakdown by ver_type
      @twilio_logs_total = TwilioLog.count
      @twilio_logs_in_range = TwilioLog.where('created_at >= ?', @start_time).count
      @twilio_breakdown = TwilioLog.where('created_at >= ?', @start_time)
                                   .group(:ver_type)
                                   .count
      
      # 3. Order Confirmations Breakdown by Status
      @order_confirmation_breakdown = OrderConfirmation.where('created_at >= ?', @start_time)
                                                       .group(:status)
                                                       .count
      
      # 4. COD Partial Payment Received Orders
      @cod_partial_payment_orders = OrderConfirmation.where('created_at >= ?', @start_time)
                                                     .where(prepaid_status: 'COD-Partial-Payment-Received')
      @cod_partial_payment_count = @cod_partial_payment_orders.count
      @cod_partial_payment_value = @cod_partial_payment_orders.pluck(:order_amount)
                                                             .map(&:to_f)
                                                             .sum
                                                             .round(2)
      
      # 5. Abandoned Cart Recovery
      @abandoned_recovered = AbandonedCart.where('created_at >= ?', @start_time)
                                         .where("LOWER(notes) = ?", "recovered")
      @abandoned_recovered_count = @abandoned_recovered.count
      
      # 6. Abandoned Cart Sales Recovery Value
      @abandoned_sales = @abandoned_recovered.pluck(:total_price)
                                            .map(&:to_f)
                                            .sum
                                            .round(2)
      
      # 7. COD-Prepaid Order Confirmation Status
      @cod_prepaid_breakdown = OrderConfirmation.where('created_at >= ?', @start_time)
                                               .where.not(prepaid_status: [nil, ''])
                                               .group(:prepaid_status)
                                               .count
      
      # Additional calculated metrics
      @abandonment_recovery_rate = calculate_percentage(@abandoned_recovered_count, @abandoned_carts_in_range)
      @average_recovered_order_value = @abandoned_recovered_count > 0 ? (@abandoned_sales / @abandoned_recovered_count).round(2) : 0
      @average_partial_payment_value = @cod_partial_payment_count > 0 ? (@cod_partial_payment_value / @cod_partial_payment_count).round(2) : 0
      
      # Pre-calculate percentages for breakdown views
      @twilio_breakdown_percentages = {}
      @twilio_breakdown.each do |ver_type, count|
        @twilio_breakdown_percentages[ver_type] = calculate_percentage(count, @twilio_logs_in_range)
      end
      
      @order_status_percentages = {}
      @order_confirmation_breakdown.each do |status, count|
        @order_status_percentages[status] = calculate_percentage(count, @order_confirmations_in_range)
      end
      
      @cod_prepaid_percentages = {}
      @cod_prepaid_breakdown.each do |status, count|
        @cod_prepaid_percentages[status] = calculate_percentage(count, @order_confirmations_in_range)
      end
    end
  
    private
  
    def calculate_start_time(time_range)
      case time_range
      when '6_hours'
        6.hours.ago
      when '24_hours'
        24.hours.ago
      when '72_hours'
        72.hours.ago
      when '7_days'
        7.days.ago
      when '30_days'
        30.days.ago
      else
        24.hours.ago
      end
    end
  
    def calculate_growth_percentage(current, total)
      return 0 if total == 0
      ((current.to_f / total) * 100).round(2)
    end
  
    def calculate_percentage(part, total)
      return 0 if total == 0
      ((part.to_f / total) * 100).round(2)
    end
  end