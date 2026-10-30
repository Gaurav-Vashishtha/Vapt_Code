# app/controllers/analytics_controller.rb
class AnalyticsController < ApplicationController
  before_action :validate_shop_id

  def daily_order_count
    days = params[:days].to_i
    return render json: { error: 'Invalid days parameter' }, status: :bad_request if days <= 0

    # ⚡ PERFORMANCE FIX: Use single query instead of 90 individual queries
    from_date = days.days.ago.to_date
    to_date = Date.current
    
    # Get all data in one query
    order_counts = OrderConfirmation
      .where(shop_id: params[:shop_id])
      .where(created_at: from_date.beginning_of_day..to_date.end_of_day)
      .where.not(status: 'Test-Order')
      .group("DATE(created_at)")
      .count
    
    # Build results array
    results = (0...days).map do |i|
      date = from_date + i
      count = order_counts[date] || 0
      
      {
        date: date.to_s,
        order_count: count
      }
    end
    
    render json: { days: days, data: results }
  end

  def overall_cod_vs_prepaid_value
    shop_id = params[:shop_id]
    days = params[:days].to_i
    
    return render json: { error: 'Invalid parameters' }, status: :bad_request if shop_id.blank? || days <= 0
    
    from_time = days.days.ago.beginning_of_day
    to_time = Time.current.end_of_day
    
    # Use ActiveRecord aggregation instead of raw SQL
    orders = OrderConfirmation
      .where(shop_id: shop_id, created_at: from_time..to_time)
      .where.not(status: 'Test-Order')
      .where.not(order_amount: [nil, ''])
    
    cod_sales = orders.where(is_cod_order: true)
                     .pluck(:order_amount)
                     .map(&:to_f)
                     .sum
                     .round(2)
    
    prepaid_sales = orders.where(is_cod_order: false)
                          .pluck(:order_amount)
                          .map(&:to_f)
                          .sum
                          .round(2)
    
    render json: {
      cod_sales: cod_sales,
      prepaid_sales: prepaid_sales
    }
  end

  def summary
    shop_id = params[:shop_id]
    days = params[:days].to_i
    
    return render json: { error: 'Missing shop_id or invalid days' }, status: :bad_request if shop_id.blank? || days <= 0
    
    from_time = days.days.ago.beginning_of_day
    to_time = Time.current.end_of_day
    
    shop = Shop.find_by(id: shop_id)
    currency_code = shop&.currency || 'INR'
    currency_symbol = Money::Currency.find(currency_code)&.symbol || currency_code
    
    orders = OrderConfirmation.where(shop_id: shop_id, created_at: from_time..to_time).where.not(status: 'Test-Order')
    cod_orders = orders.where(is_cod_order: true)
    prepaid_orders = orders.where(is_cod_order: false)
    
    verified_orders = orders.where(status: 'COD-Verified')
    partial_payment_orders = orders.where(status: 'COD-Partial-Payment-Received')
    cod_prepaid_orders = orders.where(status: 'COD-Prepaid')
    
    # Calculate partial payment value
    partial_payment_value = partial_payment_orders
      .where.not(order_amount: [nil, ''])
      .pluck(:order_amount)
      .map(&:to_f)
      .sum
      .round(2)
    
    # Calculate COD to Prepaid conversion sales value
    cod_prepaid_sales = cod_prepaid_orders
      .where.not(order_amount: [nil, ''])
      .pluck(:order_amount)
      .map(&:to_f)
      .sum
      .round(2)
    
    # Abandoned cart metrics
    abandoned_recovered = AbandonedCart
      .where(shop_id: shop_id, created_at: from_time..to_time)
      .where("LOWER(notes) = ?", "recovered")
    
    abandoned_sales = abandoned_recovered
      .where.not(total_price: [nil, ''])
      .pluck(:total_price)
      .map(&:to_f)
      .sum
      .round(2)

    shipping_stats = build_shipping_stats(orders)
    prepaid_discount_ratios = build_prepaid_discount_ratios(cod_orders, prepaid_orders, shop)

    render json: {
      shop_id: shop_id,
      days: days,
      currency: currency_symbol,
      metrics: {
        total_orders: orders.count,
        cod_orders: cod_orders.count,
        prepaid_orders: prepaid_orders.count,
        verified_orders: verified_orders.count,
        partial_payment_collected: {
          count: partial_payment_orders.count,
          value: partial_payment_value
        },
        cod_prepaid_orders: cod_prepaid_orders.count,
        cod_prepaid_sales: cod_prepaid_sales,
        abandoned_cart_recovered: abandoned_recovered.count,
        abandoned_cart_sales: abandoned_sales,
        shipping_stats: shipping_stats,
        prepaid_discount_ratios: prepaid_discount_ratios
      }
    }
  end

  # Keep other existing methods as they are
  def average_order_value
    days = params[:days].to_i
    return render json: { error: 'Invalid days parameter' }, status: :bad_request if days <= 0
  
    from_date = days.days.ago.to_date
    
    results = (0...days).map do |i|
      date = from_date + i
      start_time = date.beginning_of_day
      end_time = date.end_of_day
      
      order_amounts = OrderConfirmation
        .where(shop_id: params[:shop_id], created_at: start_time..end_time)
        .where.not(status: 'Test-Order')
        .where.not(order_amount: [nil, ''])
        .pluck(:order_amount)
        .map(&:to_f)
        .reject(&:zero?)
      
      {
        date: date.to_s,
        average_order_value: order_amounts.any? ? (order_amounts.sum / order_amounts.size).round(2) : 0.0,
        total_orders: order_amounts.size
      }
    end
    
    render json: { days: days, data: results }
  end

  def order_type_breakdown
    days = params[:days].to_i
    return render json: { error: 'Invalid days parameter' }, status: :bad_request if days <= 0
  
    from_date = days.days.ago.to_date
    
    results = (0...days).map do |i|
      date = from_date + i
      start_time = date.beginning_of_day
      end_time = date.end_of_day
      
      cod_count = OrderConfirmation
        .where(shop_id: params[:shop_id], created_at: start_time..end_time, is_cod_order: true)
        .where.not(status: 'Test-Order')
        .count
      
      prepaid_count = OrderConfirmation
        .where(shop_id: params[:shop_id], created_at: start_time..end_time, is_cod_order: false)
        .where.not(status: 'Test-Order')
        .count
      
      {
        date: date.to_s,
        cod_orders: cod_count,
        prepaid_orders: prepaid_count
      }
    end
    
    render json: { days: days, data: results }
  end

  def partial_payment_summary
    days = params[:days].to_i
    return render json: { error: 'Invalid days parameter' }, status: :bad_request if days <= 0

    from_date = days.days.ago.to_date

    results = (0...days).map do |i|
      date = from_date + i
      start_time = date.beginning_of_day
      end_time = date.end_of_day

      orders = OrderConfirmation
                 .where(shop_id: params[:shop_id], created_at: start_time..end_time, status: 'COD-Partial-Payment-Received')
                 .where.not(order_amount: [nil, ''])

      total_count = orders.count
      total_value = orders.pluck(:order_amount).map(&:to_f).sum.round(2)

      {
        date: date.to_s,
        order_count: total_count,
        order_value: total_value
      }
    end

    render json: { days: days, data: results }
  end

  def summary_analytics
    # This method is called by the routes, redirect to summary
    summary
  end

  def summary_metrics
    shop_id = params[:shop_id]
    days = params[:days].to_i
    return render json: { error: 'Missing shop_id or invalid days' }, status: :bad_request if shop_id.blank? || days <= 0
  
    from_time = days.days.ago.beginning_of_day
    to_time = Time.zone.now.end_of_day
  
    shop = Shop.find_by(id: shop_id)
    currency_code = shop&.currency || 'INR'
    currency_symbol = Money::Currency.find(currency_code)&.symbol || currency_code
  
    orders = OrderConfirmation.where(shop_id: shop_id, created_at: from_time..to_time).where.not(status: 'Test-Order')
    cod_orders = orders.where(is_cod_order: true)
    prepaid_orders = orders.where(is_cod_order: false)
  
    verified_orders = orders.where(status: 'COD-Verified')
    partial_payment_orders = orders.where(status: 'COD-Partial-Payment-Received')
    cod_prepaid_orders = orders.where(status: 'COD-Prepaid')
  
    abandoned_recovered = AbandonedCart.where(shop_id: shop_id, created_at: from_time..to_time)
                                       .where("LOWER(notes) = ?", "recovered")
    abandoned_sales = abandoned_recovered.pluck(:total_price).map(&:to_f).sum.round(2)

    shipping_stats = build_shipping_stats(orders)
    prepaid_discount_ratios = build_prepaid_discount_ratios(cod_orders, prepaid_orders, shop)

    render json: {
      shop_id: shop_id,
      days: days,
      currency: currency_symbol,
      metrics: {
        total_orders: orders.count,
        cod_orders: cod_orders.count,
        prepaid_orders: prepaid_orders.count,
        # Match `summary` / console: strict COD-Verified only (partial + prepaid have their own keys).
        verified_orders: verified_orders.count,
        partial_payment_collected: {
          count: partial_payment_orders.count,
          value: partial_payment_orders.pluck(:order_amount).map(&:to_f).sum.round(2)
        },
        cod_prepaid_orders: cod_prepaid_orders.count,
        abandoned_cart_recovered: abandoned_recovered.count,
        abandoned_cart_sales: abandoned_sales,
        shipping_stats: shipping_stats,
        prepaid_discount_ratios: prepaid_discount_ratios
      }
    }
  end
  

  # Communication methods - keep existing implementation
  def communication_summary
    shop_id = params[:shop_id]
    days = params[:days].to_i
  
    return render json: { error: 'Missing shop_id or invalid days' }, status: :bad_request if shop_id.blank? || days <= 0
  
    from_time = days.days.ago.beginning_of_day
    to_time = Time.zone.now.end_of_day
  
    # --- Twilio Logs ---
    twilio_data = TwilioLog
                    .where(shop_id: shop_id, created_at: from_time..to_time)
                    .group(:ver_type, :status)
                    .count
  
    twilio_summary = format_grouped_result(twilio_data)
  
    # --- PreOrder OTPs ---
    pre_order_data = PreOrderOtp
                       .where(shop_id: shop_id, created_at: from_time..to_time)
                       .group(:status)
                       .count
  
    pre_order_summary = {
      success: pre_order_data[true] || 0,
      failed: pre_order_data[false] || 0
    }
  
    # --- Abandoned Carts ---
    abandoned_data = AbandonedCart
                       .where(shop_id: shop_id, created_at: from_time..to_time)
                       .group(:notif_type, :status)
                       .count
  
    abandoned_summary = format_grouped_result(abandoned_data)
  
    render json: {
      shop_id: shop_id,
      days: days,
      communication_summary: {
        twilio_logs: twilio_summary,
        pre_order_otps: pre_order_summary,
        abandoned_carts: abandoned_summary
      }
    }
  end
  
  # Helper for nested grouping result
  def format_grouped_result(data)
    result = {}
    data.each do |(type, status), count|
      type_key = type.to_s
      status_key = status.to_s.downcase == 'success' ? 'success' : 'failed'
      result[type_key] ||= { success: 0, failed: 0 }
      result[type_key][status_key.to_sym] += count
    end
    result
  end

  def communication_summary_overall
    shop_id = params[:shop_id]
    days = params[:days].to_i
  
    return render json: { error: 'Missing shop_id or invalid days' }, status: :bad_request if shop_id.blank? || days <= 0
  
    from_time = days.days.ago.beginning_of_day
    to_time = Time.zone.now.end_of_day
  
    sms_total = 0
    sms_failed = 0
    whatsapp_total = 0
    whatsapp_failed = 0
  
    # --- Twilio Logs ---
    TwilioLog.where(shop_id: shop_id, created_at: from_time..to_time).group(:ver_type, :status).count.each do |(ver_type, status), count|
      channel = detect_channel(ver_type)
      next unless channel
  
      if status.to_s.downcase == 'success'
        channel == :sms ? sms_total += count : whatsapp_total += count
      else
        channel == :sms ? sms_failed += count : whatsapp_failed += count
      end
    end
  
    # --- PreOrder OTPs (SMS only) ---
    pre_order = PreOrderOtp.where(shop_id: shop_id, created_at: from_time..to_time).group(:status).count
    sms_total += pre_order[true] || 0
    sms_failed += pre_order[false] || 0
  
    # --- Abandoned Carts ---
    AbandonedCart.where(shop_id: shop_id, created_at: from_time..to_time).group(:notif_type, :status).count.each do |(notif_type, status), count|
      channel = detect_channel(notif_type)
      next unless channel
  
      if status.to_s.downcase == 'success'
        channel == :sms ? sms_total += count : whatsapp_total += count
      else
        channel == :sms ? sms_failed += count : whatsapp_failed += count
      end
    end
  
    total_success = sms_total + whatsapp_total
    total_failed = sms_failed + whatsapp_failed
    total_sent = total_success + total_failed
  
    render json: {
      shop_id: shop_id,
      days: days,
      summary: {
        sms: {
          success: sms_total,
          failed: sms_failed,
          total: sms_total + sms_failed
        },
        whatsapp: {
          success: whatsapp_total,
          failed: whatsapp_failed,
          total: whatsapp_total + whatsapp_failed
        },
        total: {
          success: total_success,
          failed: total_failed,
          total: total_sent
        }
      }
    }
  end
  
  # Helper function
  def detect_channel(type)
    return :sms if type.to_s.downcase.include?("sms")
    return :whatsapp if type.to_s.downcase.include?("whatsapp")
    nil
  end

  def daily_sales_by_order_type
    days = params[:days].to_i
    return render json: { error: 'Invalid days parameter' }, status: :bad_request if days <= 0
  
    from_date = days.days.ago.to_date
  
    results = (0...days).map do |i|
      date = from_date + i
      start_time = date.beginning_of_day
      end_time = date.end_of_day
  
      cod_sales = OrderConfirmation.where(shop_id: params[:shop_id], created_at: start_time..end_time, is_cod_order: true)
                                   .where.not(status: 'Test-Order')
                                   .where.not(order_amount: [nil, ''])
                                   .pluck(:order_amount).map(&:to_f).sum.round(2)
  
      prepaid_sales = OrderConfirmation.where(shop_id: params[:shop_id], created_at: start_time..end_time, is_cod_order: false)
                                       .where.not(status: 'Test-Order')
                                       .where.not(order_amount: [nil, ''])
                                       .pluck(:order_amount).map(&:to_f).sum.round(2)
  
      {
        date: date.to_s,
        cod_sales: cod_sales,
        prepaid_sales: prepaid_sales
      }
    end
  
    render json: { days: days, data: results }
  end

  def overall_cod_vs_prepaid_value
    days = params[:days].to_i
    return render json: { error: 'Invalid days parameter' }, status: :bad_request if days <= 0
  
    from_time = days.days.ago.beginning_of_day
    to_time = Time.zone.now.end_of_day
  
    cod_sales = OrderConfirmation.where(shop_id: params[:shop_id], created_at: from_time..to_time, is_cod_order: true)
                                 .where.not(status: 'Test-Order')
                                 .where.not(order_amount: [nil, ''])
                                 .pluck(:order_amount).map(&:to_f).sum.round(2)
  
    prepaid_sales = OrderConfirmation.where(shop_id: params[:shop_id], created_at: from_time..to_time, is_cod_order: false)
                                     .where.not(status: 'Test-Order')
                                     .where.not(order_amount: [nil, ''])
                                     .pluck(:order_amount).map(&:to_f).sum.round(2)
  
    render json: {
      days: days,
      cod_sales: cod_sales,
      prepaid_sales: prepaid_sales
    }
  end

  def daily_order_count
    days = params[:days].to_i
    return render json: { error: 'Invalid days parameter' }, status: :bad_request if days <= 0
  
    from_date = days.days.ago.to_date
  
    results = (0...days).map do |i|
      date = from_date + i
      start_time = date.beginning_of_day
      end_time = date.end_of_day
  
      order_count = OrderConfirmation.where(shop_id: params[:shop_id], created_at: start_time..end_time)
                                     .where.not(status: 'Test-Order')
                                     .count
  
      {
        date: date.to_s,
        order_count: order_count
      }
    end
  
    render json: { days: days, data: results }
  end

  def daily_total_sales
    days = params[:days].to_i
    return render json: { error: 'Invalid days parameter' }, status: :bad_request if days <= 0
  
    from_date = days.days.ago.to_date
  
    results = (0...days).map do |i|
      date = from_date + i
      start_time = date.beginning_of_day
      end_time = date.end_of_day
  
      total_sales = OrderConfirmation.where(shop_id: params[:shop_id], created_at: start_time..end_time)
                                     .where.not(status: 'Test-Order')
                                     .where.not(order_amount: [nil, ''])
                                     .pluck(:order_amount).map(&:to_f).sum.round(2)
  
      {
        date: date.to_s,
        total_sales: total_sales
      }
    end
  
    render json: { days: days, data: results }
  end

  def fast_dashboard
    shop = Shop.find_by(id: params[:shop_id])
    return render json: { error: "Shop not found" }, status: :not_found if shop.blank?

    days = params[:days].to_i
    days = FastDashboardBuilder::DEFAULT_WINDOW_DAYS unless days.positive?
    refresh = ActiveModel::Type::Boolean.new.cast(params[:refresh])

    payload = FastDashboardBuilder.call(shop: shop, window_days: days, refresh: refresh)
    render json: payload
  end

  def form_funnel
    shop = Shop.find_by(id: params[:shop_id])
    return render json: { error: "Shop not found" }, status: :not_found if shop.blank?

    days = params[:days].to_i
    days = FastDashboardBuilder::DEFAULT_WINDOW_DAYS unless days.positive?

    render json: { funnel: FastDashboardBuilder.funnel_for(shop: shop, window_days: days) }
  end

  private

  def validate_shop_id
    return render json: { error: 'Missing shop_id parameter' }, status: :bad_request if params[:shop_id].blank?
  end

  # Fulfillment / shipment_status values from Shopify (e.g. delivered, undelivered, in_transit).
  # Terminal outcomes: delivered vs undelivered (often used for delivery vs RTO-style outcomes).
  def build_shipping_stats(orders)
    rows = orders.where.not(shipping_status: [nil, '']).pluck(:shipping_status, :is_cod_order)
    by_status = Hash.new(0)
    by_payment_and_status = Hash.new(0)

    rows.each do |status, is_cod|
      key = status.to_s.strip.downcase
      next if key.blank?

      by_status[key] += 1
      pt = is_cod ? 'cod' : 'prepaid'
      by_payment_and_status[[pt, key]] += 1
    end

    delivered = by_status['delivered'] || 0
    undelivered_keys = %w[
      undelivered
      failure
      failed
      restock
      restocked
      mark
      marked
      rto
    ].freeze
    undelivered = undelivered_keys.sum { |k| by_status[k] || 0 }
    terminal_total = delivered + undelivered

    other_statuses = by_status.except('delivered', *undelivered_keys)

    {
      delivered_count: delivered,
      undelivered_count: undelivered,
      terminal_total: terminal_total,
      delivered_pct: terminal_total.positive? ? ((delivered.to_f / terminal_total) * 100).round(1) : nil,
      undelivered_pct: terminal_total.positive? ? ((undelivered.to_f / terminal_total) * 100).round(1) : nil,
      with_status_total: by_status.values.sum,
      missing_status_count: orders.where(shipping_status: [nil, '']).count,
      by_status: by_status.sort_by { |_, v| -v }.to_h,
      other_statuses: other_statuses.sort_by { |_, v| -v }.to_h,
      by_payment_type: build_shipping_by_payment_type(by_payment_and_status)
    }
  end

  def build_shipping_by_payment_type(by_payment_and_status)
    %w[cod prepaid].index_with do |pt|
      del = by_payment_and_status[[pt, 'delivered']] || 0
      undelivered_keys = %w[
        undelivered
        failure
        failed
        restock
        restocked
        mark
        marked
        rto
      ].freeze
      und = undelivered_keys.sum { |k| by_payment_and_status[[pt, k]] || 0 }
      term = del + und
      {
        delivered_count: del,
        undelivered_count: und,
        terminal_total: term,
        delivered_pct: term.positive? ? ((del.to_f / term) * 100).round(1) : nil,
        undelivered_pct: term.positive? ? ((und.to_f / term) * 100).round(1) : nil
      }
    end
  end

  def shop_has_full_payment_prepaid_discount?(shop)
    return false if shop.blank?

    setting = shop.setting
    return false unless setting&.partial_payment_enabled

    PartialRuleSet.where(shop_id: shop.id, is_enabled: true)
                  .where(amount_type: 'percentage')
                  .where('amount >= ?', 99.99)
                  .where('discount_value > ?', 0)
                  .exists?
  end

  def build_prepaid_discount_ratios(cod_orders_scope, prepaid_orders_scope, shop)
    unless shop_has_full_payment_prepaid_discount?(shop)
      return { eligible: false }
    end

    cod_c = cod_orders_scope.count
    pre_c = prepaid_orders_scope.count
    tot = cod_c + pre_c
    {
      eligible: true,
      cod_orders: cod_c,
      prepaid_orders: pre_c,
      total_classification_orders: tot,
      prepaid_pct: tot.positive? ? ((pre_c.to_f / tot) * 100).round(1) : nil,
      cod_pct: tot.positive? ? ((cod_c.to_f / tot) * 100).round(1) : nil
    }
  end
end