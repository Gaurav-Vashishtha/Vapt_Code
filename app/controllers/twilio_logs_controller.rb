require "csv"

class TwilioLogsController < AuthenticatedController
  before_action :set_shop, only: [:index, :message_logs, :cod_payment_logs, :cod_payment_logs_export, :cod_king_abandoned_carts, :cod_king_abandoned_carts_export]

  # GET /twilio_logs
  # GET /twilio_logs.json
  def index
    @order_confirmations = @shop.order_confirmations.where.not(status: 'Non-COD')
    
    # Extract days parameter and set up date range
    days = params[:days].blank? ? 7 : params[:days].to_i
    days = 1 if days <= 0 || days > 365 # Reasonable limits
    date_range = days.days.ago.beginning_of_day..Time.current.end_of_day
    
    # Apply filters with date range
    if params[:query].present? || params[:days].present?
      @order_confirmations = @order_confirmations
        .where(created_at: date_range)
        .where(
          'order_number ILIKE ? OR customer_name ILIKE ? OR order_id ILIKE ? OR order_confirmations.status ILIKE ?',
          "%#{params[:query]}%", "%#{params[:query]}%", "%#{params[:query]}%", "%#{params[:query]}%"
        )
    end
    
    # COD fees calculation (already filtered by date)
    cod_fees_total = @order_confirmations.sum(:cod_fee)
    
    # 🚀 CRITICAL OPTIMIZATION 1: Single aggregated TwilioLog query
    # Replaces 4+ separate queries with 1 grouped query
    twilio_stats = TwilioLog.where(shop_id: @shop.id, created_at: date_range)
      .group(:ver_type, :status)
      .count
    
    confirmation_sms_count = twilio_stats[['Confirmation-SMS', 'SUCCESS']] || 0
    fulfilment_sms_count = twilio_stats[['Fulfilment-SMS', 'SUCCESS']] || 0
    sms_other_count = twilio_stats[['SMS', 'SUCCESS']] || 0
    whatsapp_twilio_count = (
      (twilio_stats[['WHATSAPP', 'SUCCESS']] || 0) +
      (twilio_stats[['WHATSAPP-CONFIRMATION', 'SUCCESS']] || 0) +
      (twilio_stats[['WHATSAPP-FULFILMENT', 'SUCCESS']] || 0) + 
      (twilio_stats[['WHATSAPP_COD_PREPAID', 'SUCCESS']] || 0) +
      (twilio_stats[['WHATSAPP_FIRST_PURCHASE', 'SUCCESS']] || 0)
    )
    
    # 🚀 CRITICAL OPTIMIZATION 2: Single aggregated AbandonedCart query
    # Replaces 3+ separate queries with 1 grouped query
    abandoned_stats = AbandonedCart.where(shop_id: @shop.id, created_at: date_range)
      .group(:status, :notif_type, :notes)
      .count
    
    ac_count_sms = abandoned_stats[['SUCCESS', 'SMS', nil]] || 0
    ac_count_whatsapp = abandoned_stats[['SUCCESS', 'WHATSAPP', nil]] || 0
    
    # 🚀 CRITICAL OPTIMIZATION 3: Combine abandoned cart recovery metrics in single query
    abandoned_cart_metrics = AbandonedCart.where(
      shop_id: @shop.id, 
      created_at: date_range, 
      notes: 'Recovered'
    ).pick(Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(total_price), 0)'))
    
    abandoned_carts_recovered = abandoned_cart_metrics&.first || 0
    abandoned_cart_total_value = abandoned_cart_metrics&.second || 0
    
    # 🚀 OPTIMIZATION 4: Single PreOrderOtp query
    pre_order_success_count = PreOrderOtp.where(
      shop_id: @shop.id, 
      created_at: date_range, 
      status: 'SUCCESS'
    ).count
    
    # BSP WhatsApp (Meta Cloud API) — sent via WhatsappMessageLog. Count only
    # rows Meta has actually accepted; mirrors the `.chargeable` filter.
    bsp_whatsapp_count = WhatsappMessageLog
                          .where(shop_id: @shop.id, created_at: date_range)
                          .where(status: %i[sent delivered read])
                          .count

    # Calculate totals
    other_sms = pre_order_success_count + sms_other_count
    whatsapp_messages = whatsapp_twilio_count + ac_count_whatsapp + bsp_whatsapp_count
    total_message_count = confirmation_sms_count + fulfilment_sms_count + other_sms + whatsapp_messages + ac_count_sms
    
    # 🚀 SAFE OPTIMIZATION: Individual status counts without GROUP BY
    # Build the exact same WHERE conditions as @order_confirmations
    base_conditions = { shop_id: @shop.id }
    base_conditions[:created_at] = date_range if params[:query].present? || params[:days].present?
    
    search_conditions = if params[:query].present?
      [
        'order_number ILIKE ? OR customer_name ILIKE ? OR order_id ILIKE ? OR status ILIKE ?',
        "%#{params[:query]}%", "%#{params[:query]}%", "%#{params[:query]}%", "%#{params[:query]}%"
      ]
    else
      nil
    end
    
    # Create base scope for status counts
    base_scope = OrderConfirmation.where.not(status: 'Non-COD').where(base_conditions)
    base_scope = base_scope.where(search_conditions) if search_conditions
    
    verified_count = base_scope.where(status: 'COD-Verified').count
    pending_count = base_scope.where(status: 'Pending').count
    cancelled_count = base_scope.where(status: 'COD-Auto-Cancelled').count
    prepaid_count = base_scope.where(status: 'COD-Prepaid').count
    manual_count = base_scope.where(status: 'COD-Manual-Verified').count
    
    # 🚀 OPTIMIZATION 6: Efficient pagination with preloading
    # Prevents N+1 queries when loading twilio_logs
    @pagy, @records = pagy(
      @order_confirmations.with_logs.includes(:twilio_logs), 
      items: 10
    )
    
    # 🚀 OPTIMIZATION 7: Calculate shipping cost efficiently
    shipping_cost_total = cancelled_count * 
                         (@shop.setting&.shipping_cost || 0) * 
                         (@shop.currency == 'INR' ? 80.0 : 1.0)
    
    render json: {
      data: serialize_order_confirmations(@records),
      total: @order_confirmations.count,
      verified: verified_count,
      pending: pending_count,
      cancelled: cancelled_count,
      prepaid: prepaid_count,
      manual: manual_count,
      cod_fees_total: cod_fees_total,
      abandoned_recovered: abandoned_carts_recovered,
      abandoned_total: abandoned_cart_total_value,
      confirmation_sms_count: confirmation_sms_count,
      fulfilment_sms_count: fulfilment_sms_count,
      other_sms: other_sms,
      ac_count_sms: ac_count_sms,
      ac_count_whatsapp: ac_count_whatsapp,
      bsp_whatsapp_count: bsp_whatsapp_count,
      whatsapp_messages: whatsapp_messages,
      total_message_count: total_message_count,
      shipping_cost_total: shipping_cost_total,
      pagy: pagy_metadata(@pagy)
    }
  end

  # GET /twilio_logs/message_logs
  # GET /twilio_logs/message_logs.json
  def message_logs
    # Extract days parameter for consistent filtering
    days = params[:days].present? ? params[:days].to_i : 30
    days = 1 if days <= 0 || days > 365
    date_range = days.days.ago.beginning_of_day..Time.current.end_of_day
    
    case params[:type]
    when "abandoned_checkout"
      @message_logs = fetch_abandoned_checkout_logs(date_range)
    when "pre_order_otp"
      @message_logs = fetch_pre_order_otp_logs(date_range)
    when "otp", "conf_sms", "fulfill_sms"
      @message_logs = fetch_specific_twilio_logs(params[:type], date_range)
    else
      @message_logs = fetch_all_message_logs(date_range)
    end
    
    # Apply search filter if present
    if params[:query].present?
      query = params[:query].to_s.downcase
      @message_logs.select! do |log|
        (log[:customer_number]&.include?(query)) || 
        (log[:order_id]&.to_s&.include?(query))
      end
    end
    
    # Apply order status filter if present
    if params[:order_status].present? && params[:order_status] != "all"
      @message_logs.select! { |log| log[:order_status]&.to_s == params[:order_status] }
    end
    
    # Sort by created_at descending
    @message_logs.sort_by! { |log| log[:created_at] || Time.at(0) }.reverse!
    
    # Pagination
    total_items = @message_logs.size
    page = params[:page].to_i > 0 ? params[:page].to_i : 1
    per_page = 10
    offset = (page - 1) * per_page
    @message_logs = @message_logs.slice(offset, per_page) || []
    
    # Format cart_details efficiently
    format_cart_details!(@message_logs)
    
    render json: {
      data: @message_logs,
      pagy: {
        page: page,
        pages: (total_items.to_f / per_page).ceil,
        items: total_items
      },
      total_count: total_items
    }
  end

  # GET /twilio_logs/cod_payment_logs
  # GET /twilio_logs/cod_payment_logs.json
  def cod_payment_logs
    # Extract days parameter for consistent filtering
    days = params[:days].present? ? params[:days].to_i : 30
    days = 1 if days <= 0 || days > 365
    
    # Get payment type from params, default to :all
    payment_type = params[:payment_type]&.to_sym || :all
    
    # Fetch COD payment orders
    @cod_orders = cod_payment_received_orders(days, payment_type)
    
    # Apply search filter if present
    if params[:query].present?
      query = "%#{params[:query]}%"
      @cod_orders = @cod_orders.where(
        'order_number ILIKE ? OR customer_name ILIKE ? OR order_id ILIKE ?',
        query, query, query
      )
    end
    
    # Get total count before pagination
    total_count = @cod_orders.count
    total_cod_fee = @cod_orders.sum(:cod_fee)

    
    # Pagination
    page = params[:page].to_i > 0 ? params[:page].to_i : 1
    per_page = 10
    offset = (page - 1) * per_page
    
    @cod_orders = @cod_orders.limit(per_page).offset(offset)
    
    # Serialize the data
    cod_logs = @cod_orders.map do |order|
      {
        id: order.id,
        order_number: order.order_number,
        order_id: order.order_id,
        customer_name: order.customer_name,
        order_total: order.order_amount, # Changed from order_total to order_amount
        cod_fee: order.cod_fee,
        status: order.status,
        created_at: order.created_at,
        updated_at: order.updated_at
      }
    end
    
    render json: {
      data: cod_logs,
      pagy: {
        page: page,
        pages: (total_count.to_f / per_page).ceil,
        items: total_count
      },
      total_count: total_count,
      total_cod_fee: total_cod_fee
    }
  end

  # GET /twilio_logs/cod_payment_logs_export
  # Export current transaction-charge filters from Usage Logs to CSV.
  def cod_payment_logs_export
    days = params[:days].present? ? params[:days].to_i : 30
    days = 1 if days <= 0 || days > 365

    payment_type = params[:payment_type]&.to_sym || :all
    scope = cod_payment_received_orders(days, payment_type)

    if params[:query].present?
      query = "%#{params[:query]}%"
      scope = scope.where(
        'order_number ILIKE ? OR customer_name ILIKE ? OR order_id ILIKE ?',
        query, query, query
      )
    end

    csv_string = CSV.generate(headers: true) do |csv|
      csv << [
        "Date",
        "Order Number",
        "Customer Name",
        "Order Total",
        "COD Fee",
        "Status"
      ]
      scope.find_each(batch_size: 500, order: :desc) do |order|
        csv << [
          order.created_at&.iso8601,
          order.order_number,
          order.customer_name,
          order.order_amount.to_f,
          order.cod_fee.to_f,
          order.status
        ]
      end
    end

    send_data(
      csv_string,
      filename: "usage-logs-transaction-charges-#{Time.current.strftime('%Y%m%d-%H%M%S')}.csv",
      type: "text/csv"
    )
  end

  # GET /twilio_logs/cod_king_abandoned_carts
  # Returns PreOrderOtp rows where checkout status is AbandonedCheckout.
  def cod_king_abandoned_carts
    date_range = begin
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date].to_s).beginning_of_day
        end_date = Date.parse(params[:end_date].to_s).end_of_day
        start_date..end_date
      else
        days = params[:days].present? ? params[:days].to_i : 30
        days = 1 if days <= 0 || days > 365
        days.days.ago.beginning_of_day..Time.current.end_of_day
      end
    rescue ArgumentError
      30.days.ago.beginning_of_day..Time.current.end_of_day
    end

    scope = @shop.pre_order_otps
      .where(created_at: date_range, order_status: "AbandonedCheckout")
      .where("cart_details IS NOT NULL")
      .where("array_length(cart_details, 1) > 0")
      .order(created_at: :desc)

    if params[:query].present?
      q = "%#{params[:query].to_s.strip}%"
      scope = scope.where("phone ILIKE :q", q: q)
    end

    page = params[:page].to_i > 0 ? params[:page].to_i : 1
    per_page = 10
    total_count = scope.count
    records = scope.limit(per_page).offset((page - 1) * per_page)

    render json: {
      data: records.map { |otp| serialize_cod_king_abandoned_cart(otp) },
      pagy: {
        page: page,
        pages: (total_count.to_f / per_page).ceil,
        items: total_count
      },
      total_count: total_count
    }
  end

  # GET /twilio_logs/cod_king_abandoned_carts_export
  # Export current COD King abandoned carts filters to CSV.
  def cod_king_abandoned_carts_export
    date_range = begin
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date].to_s).beginning_of_day
        end_date = Date.parse(params[:end_date].to_s).end_of_day
        start_date..end_date
      else
        days = params[:days].present? ? params[:days].to_i : 30
        days = 1 if days <= 0 || days > 365
        days.days.ago.beginning_of_day..Time.current.end_of_day
      end
    rescue ArgumentError
      30.days.ago.beginning_of_day..Time.current.end_of_day
    end

    scope = @shop.pre_order_otps
      .where(created_at: date_range, order_status: "AbandonedCheckout")
      .where("cart_details IS NOT NULL")
      .where("array_length(cart_details, 1) > 0")
      .order(created_at: :desc)

    if params[:query].present?
      q = "%#{params[:query].to_s.strip}%"
      scope = scope.where("phone ILIKE :q", q: q)
    end

    csv_string = CSV.generate(headers: true) do |csv|
      csv << [
        "Phone",
        "Country",
        "Timestamp",
        "Verification Status",
        "Cart Details",
        "Permalink"
      ]
      scope.find_each(batch_size: 500) do |otp|
        cart_details = otp.cart_details.is_a?(Array) ? otp.cart_details : []
        cart_text = cart_details.map do |item|
          next if !item.is_a?(Hash)
          qty = item["quantity"].to_i
          title = item["title"].to_s
          "#{qty.positive? ? qty : 1} x #{title}"
        end.compact.join(" | ")
        permalink = build_shopify_permalink(cart_details)

        csv << [
          otp.phone,
          otp.country_code,
          otp.created_at&.iso8601,
          otp.verification_status,
          cart_text,
          permalink
        ]
      end
    end

    send_data(
      csv_string,
      filename: "cod-king-abandoned-carts-#{Time.current.strftime('%Y%m%d-%H%M%S')}.csv",
      type: "text/csv"
    )
  end

  def cod_partial_payment_orders(days = 7)
    @shop.order_confirmations
      .where(status: 'COD-Partial-Payment-Received')
      .where('created_at >= ?', days.days.ago)
      .order(created_at: :desc)
  end

  def cod_prepaid_orders(days = 7)
    @shop.order_confirmations
      .where(status: 'COD-Prepaid')
      .where('created_at >= ?', days.days.ago)
      .order(created_at: :desc)
  end

  # FIXED: Removed 'shop' parameter - use 'self' implicitly
  def cod_payment_received_orders(days = 7, payment_type = :all)
    base_query = @shop.order_confirmations
      .where('created_at >= ?', days.days.ago)
      .order(created_at: :desc)
  
    case payment_type
    when :partial
      base_query.where(status: 'COD-Partial-Payment-Received')
    when :prepaid
      base_query.where(status: 'COD-Prepaid')
    when :all
      base_query.where(status: ['COD-Partial-Payment-Received', 'COD-Prepaid'])
    else
      base_query.none
    end
  end

  private

  # 🚀 OPTIMIZATION: Custom serialization to avoid heavy include: :twilio_logs
  def serialize_order_confirmations(records)
    records.map do |record|
      {
        id: record.id,
        order_number: record.order_number,
        order_id: record.order_id,
        customer_name: record.customer_name,
        status: record.status,
        cod_fee: record.cod_fee,
        created_at: record.created_at,
        updated_at: record.updated_at,
        twilio_logs: record.twilio_logs.map do |log|
          {
            id: log.id,
            status: log.status,
            ver_type: log.ver_type,
            customer_number: log.customer_number,
            country_code: log.country_code,
            created_at: log.created_at,
            sid: log.sid,
            is_charged: log.is_charged
          }
        end
      }
    end
  end

  # Optimized method to fetch abandoned checkout logs
  def fetch_abandoned_checkout_logs(date_range)
    @shop.abandoned_carts
      .where(shopify_created_at: date_range)
      .select('status, phone as customer_number, country_code, shopify_created_at as created_at')
      .distinct
      .map(&:attributes)
      .map(&:symbolize_keys)
  end

  # Optimized method to fetch pre-order OTP logs
  def fetch_pre_order_otp_logs(date_range)
    @shop.pre_order_otps.otp_sends
      .where(created_at: date_range)
      .select('status, order_status, phone as customer_number, country_code, created_at, cart_details')
      .map(&:attributes)
      .map(&:symbolize_keys)
  end

  # Optimized method to fetch specific Twilio logs
  def fetch_specific_twilio_logs(type, date_range)
    type_map = {
      "otp" => "SMS",
      "conf_sms" => "Confirmation-SMS",
      "fulfill_sms" => "Fulfilment-SMS"
    }
    ver_type = type_map[type]
    
    @shop.order_confirmations
      .joins(:twilio_logs)
      .where(twilio_logs: { ver_type: ver_type, created_at: date_range })
      .select('order_confirmations.order_id, twilio_logs.ver_type, twilio_logs.country_code, twilio_logs.customer_number, twilio_logs.created_at, twilio_logs.status')
      .distinct
      .map(&:attributes)
      .map(&:symbolize_keys)
  end

  # Optimized method to fetch all message logs
  def fetch_all_message_logs(date_range)
    # Fetch all three types separately to avoid complex unions
    abandoned_carts = fetch_abandoned_checkout_logs(date_range)
    pre_order_otps = fetch_pre_order_otp_logs(date_range)
    
    # Add verification_status for pre_order_otps in combined view
    pre_order_otps_with_verification = @shop.pre_order_otps.otp_sends
      .where(created_at: date_range)
      .select('status, order_status, phone as customer_number, country_code, created_at, cart_details, verification_status')
      .map(&:attributes)
      .map(&:symbolize_keys)
    
    twilio_logs = @shop.order_confirmations
      .joins(:twilio_logs)
      .where(twilio_logs: { created_at: date_range })
      .select('order_confirmations.order_id, twilio_logs.ver_type, twilio_logs.country_code, twilio_logs.customer_number, twilio_logs.created_at, twilio_logs.status')
      .distinct
      .map(&:attributes)
      .map(&:symbolize_keys)
    
    abandoned_carts + pre_order_otps_with_verification + twilio_logs
  end

  # Efficiently format cart details in place
  def format_cart_details!(message_logs)
    message_logs.each do |log|
      if log[:cart_details].present? && log[:cart_details].is_a?(Array)
        cart_items = log[:cart_details].map do |item|
          title = item['title'].to_s.gsub(/^Partial Payment for /, '').strip
          quantity = item['quantity'].to_s.presence || "1"
          price = item['price'].to_s.presence || "-"
          "#{quantity} x #{title} - price: #{price}"
        end
        log[:cart_items] = cart_items.join("; ")
      end
    end
  end

  def serialize_cod_king_abandoned_cart(otp)
    cart_details = otp.cart_details.is_a?(Array) ? otp.cart_details : []
    total_cart_value = cart_details.sum do |item|
      item_price = item.is_a?(Hash) ? item["price"].to_f : 0.0
      item_qty = item.is_a?(Hash) ? item["quantity"].to_i : 0
      item_price * (item_qty.positive? ? item_qty : 1)
    end

    customer, recent_shipping_address = customer_context_for(otp.phone)

    {
      id: otp.id,
      created_at: otp.created_at,
      customer_number: otp.phone,
      country_code: otp.country_code,
      device_id: otp.device_id,
      shopify_order_ids: otp.shopify_order_ids,
      order_status: otp.order_status,
      verification_status: otp.verification_status,
      ver_type: otp.ver_type,
      status: otp.status,
      cart_details: cart_details,
      total_cart_value: total_cart_value,
      customer: customer,
      recent_shipping_address: recent_shipping_address
    }
  end

  def customer_context_for(raw_phone)
    phone = raw_phone.to_s.strip
    return [nil, nil] if phone.blank?

    variants = [phone, phone.delete(" ")]
    normalized = phone.delete(" ")
    variants << "+#{normalized}" unless normalized.start_with?("+")
    variants.uniq!

    customer = Customer.where(phone: variants).order(updated_at: :desc).first
    return [nil, nil] if customer.blank?

    shipping = customer.customer_addresses.order(updated_at: :desc).limit(1).first

    customer_payload = {
      id: customer.id,
      phone: customer.phone,
      first_name: customer.first_name,
      last_name: customer.last_name,
      email: customer.email
    }

    shipping_payload = if shipping.present?
      {
        first_name: shipping.first_name,
        last_name: shipping.last_name,
        phone: shipping.phone,
        address1: shipping.address1,
        address2: shipping.address2,
        city: shipping.city,
        province: shipping.province,
        country: shipping.country,
        zip: shipping.zip,
        country_code: shipping.country_code
      }
    end

    [customer_payload, shipping_payload]
  end

  def build_shopify_permalink(cart_details)
    return "" unless @shop&.shopify_domain.present? && cart_details.is_a?(Array)

    line_items = cart_details.map do |item|
      next unless item.is_a?(Hash)
      variant_id = item["variant_id"] || item["variantId"]
      qty = item["quantity"].to_i
      next if variant_id.blank?
      "#{variant_id}:#{qty.positive? ? qty : 1}"
    end.compact
    return "" if line_items.empty?

    "https://#{@shop.shopify_domain}/cart/#{line_items.join(',')}?storefront=true"
  end
end