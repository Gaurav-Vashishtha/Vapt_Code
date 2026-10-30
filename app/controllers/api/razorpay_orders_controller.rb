# frozen_string_literal: true

class Api::RazorpayOrdersController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :verify, :callback]

  # POC: Hardcoded Razorpay credentials (test mode)
  RAZORPAY_KEY_ID = 'rzp_test_SHj8cWsiSU6T9c'
  RAZORPAY_KEY_SECRET = 'NALbfeh1E2rMrLvz23eC7LKV'

  def create
    cart_data = params[:cart_data] || params[:cart]
    shipping_address = params[:shipping_address] || params[:shippingAddress]
    buyer_identity = params[:buyer_identity] || params[:buyerIdentity] || {}
    payment_amount = params[:payment_amount] || params[:paymentAmount]
    selected_rule_id = params[:selected_rule_id] || params[:selectedRuleId]
    return_url = params[:return_url] || params[:returnUrl]
    shipping_rate_details = params[:shipping_rate_details] || params[:shippingRateDetails]
    shop_domain = params[:shop_domain] || params[:shop] || extract_shop_from_origin

    # Validate required parameters
    unless cart_data && shipping_address && payment_amount
      return render json: { 
        error: 'Missing required parameters',
        message: 'cart_data, shipping_address, and payment_amount are required' 
      }, status: :bad_request
    end

    unless cart_data[:items] || cart_data['items']
      return render json: { 
        error: 'Invalid cart data',
        message: 'cart must contain items' 
      }, status: :bad_request
    end

    # Find shop by domain
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      return render json: { 
        error: 'Shop not found',
        message: "Shop with domain '#{shop_domain}' not found" 
      }, status: :not_found
    end

    # Call service to create Razorpay order
    result = RazorpayServices::OrderCreateService.call(
      shop,
      cart_data,
      shipping_address,
      buyer_identity,
      payment_amount.to_f,
      selected_rule_id,
      return_url,
      shipping_rate_details
    )

    if result[:error]
      render json: { 
        error: result[:error],
        errors: result[:errors] 
      }, status: :unprocessable_entity
    else
      render json: {
        success: true,
        razorpay_order_id: result[:razorpay_order_id],
        amount: result[:amount],
        currency: result[:currency],
        key_id: RAZORPAY_KEY_ID,
        order_data: result[:order_data]
      }, status: :created
    end
  rescue StandardError => e
    Rails.logger.error "Error in RazorpayOrdersController#create: #{e.message} #{e.backtrace.first(5).join("\n")}"
    render json: { 
      error: 'Internal server error',
      message: e.message 
    }, status: :internal_server_error
  end

  def verify
    # Accept both Razorpay-style (razorpay_*) and shorthand (payment_id, order_id, signature) param names
    razorpay_payment_id = params[:razorpay_payment_id] || params[:razorpayPaymentId] || params[:payment_id]
    razorpay_order_id = params[:razorpay_order_id] || params[:razorpayOrderId] || params[:order_id]
    razorpay_signature = params[:razorpay_signature] || params[:razorpaySignature] || params[:signature]
    shop_domain = params[:shop_domain] || params[:shop] || extract_shop_from_origin

    # Validate required parameters
    unless razorpay_payment_id && razorpay_order_id && razorpay_signature
      return render json: { 
        error: 'Missing required parameters',
        message: 'razorpay_payment_id, razorpay_order_id, and razorpay_signature are required' 
      }, status: :bad_request
    end

    # Find shop by domain
    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      return render json: { 
        error: 'Shop not found',
        message: "Shop with domain '#{shop_domain}' not found" 
      }, status: :not_found
    end

    # Call service to verify payment and create order
    result = RazorpayServices::PaymentVerifyService.call(
      shop,
      razorpay_payment_id,
      razorpay_order_id,
      razorpay_signature
    )

    if result[:error]
      render json: { 
        error: result[:error],
        errors: result[:errors] 
      }, status: :unprocessable_entity
    else
      render json: {
        success: true,
        order: {
          id: result[:order_id],
          number: result[:order_number],
          name: result[:order_name],
          total_price: result[:total_price],
          currency_code: result[:currency_code],
          order_status_url: result[:order_status_url]
        },
        payment: {
          id: result[:payment_id],
          amount: result[:payment_amount],
          status: result[:payment_status]
        }
      }, status: :ok
    end
  rescue StandardError => e
    Rails.logger.error "Error in RazorpayOrdersController#verify: #{e.message} #{e.backtrace.first(5).join("\n")}"
    render json: { 
      error: 'Internal server error',
      message: e.message 
    }, status: :internal_server_error
  end

  # Razorpay redirects the browser here after successful payment (e.g. UPI) when callback_url is set.
  # Handler may not fire in iframe/WebView, so this ensures we still verify and complete the order.
  def callback
    razorpay_payment_id = params[:razorpay_payment_id] || params[:razorpayPaymentId]
    razorpay_order_id = params[:razorpay_order_id] || params[:razorpayOrderId]
    razorpay_signature = params[:razorpay_signature] || params[:razorpaySignature]
    shop_domain = params[:shop] || extract_shop_from_origin

    unless razorpay_payment_id && razorpay_order_id && razorpay_signature
      Rails.logger.error "Razorpay callback: missing params"
      redirect_to_fallback_with_error(shop_domain, "Missing payment details")
      return
    end

    shop = Shop.find_by(shopify_domain: shop_domain)
    unless shop
      Rails.logger.error "Razorpay callback: shop not found #{shop_domain}"
      redirect_to_fallback_with_error(shop_domain, "Shop not found")
      return
    end

    result = RazorpayServices::PaymentVerifyService.call(
      shop,
      razorpay_payment_id,
      razorpay_order_id,
      razorpay_signature
    )

    if result[:error]
      Rails.logger.error "Razorpay callback verify failed: #{result[:error]}"
      redirect_to_fallback_with_error(shop_domain, result[:error])
      return
    end

    # Prefer redirect to Shopify order status page when available
    if result[:order_status_url].present?
      redirect_to result[:order_status_url], allow_other_host: true
      return
    end

    # Fallback: redirect back to store with success params (return_url from order notes, or default)
    return_url = result[:return_url].presence || result["return_url"].presence
    return_url ||= "https://#{shop_domain}"
    base = return_url.include?("?") ? "#{return_url}&" : "#{return_url}?"
    fallback_params = "razorpay_success=1&order_number=#{result[:order_number]}"
    fallback_params += "&order_status_url=#{ERB::Util.url_encode(result[:order_status_url])}" if result[:order_status_url].present?
    redirect_to "#{base}#{fallback_params}", allow_other_host: true
  rescue StandardError => e
    Rails.logger.error "Razorpay callback error: #{e.message} #{e.backtrace.first(5).join("\n")}"
    redirect_to_fallback_with_error(params[:shop], e.message)
  end

  private

  def redirect_to_fallback_with_error(shop_domain, message)
    url = shop_domain.present? ? "https://#{shop_domain}?razorpay_error=#{ERB::Util.url_encode(message)}" : "/"
    redirect_to url, allow_other_host: true
  end

  def extract_shop_from_origin
    # Try to extract shop domain from Origin header or Referer
    origin = request.headers['Origin'] || request.headers['Referer']
    return nil unless origin
    
    # Extract myshopify.com domain from origin URL
    match = origin.match(/https?:\/\/([a-zA-Z0-9-]+\.myshopify\.com)/)
    match ? match[1] : nil
  end
end
