# frozen_string_literal: true

require "razorpay"
require "openssl"

module RazorpayServices
  class PaymentVerifyService
    # POC: Hardcoded Razorpay credentials (test mode)
    RAZORPAY_KEY_ID = 'rzp_test_SHj8cWsiSU6T9c'
    RAZORPAY_KEY_SECRET = 'NALbfeh1E2rMrLvz23eC7LKV'

    attr_reader :shop, :razorpay_payment_id, :razorpay_order_id, :razorpay_signature

    def initialize(shop, razorpay_payment_id, razorpay_order_id, razorpay_signature)
      @shop = shop
      @razorpay_payment_id = razorpay_payment_id
      @razorpay_order_id = razorpay_order_id
      @razorpay_signature = razorpay_signature
    end

    def self.call(shop, razorpay_payment_id, razorpay_order_id, razorpay_signature)
      new(shop, razorpay_payment_id, razorpay_order_id, razorpay_signature).call
    end

    def call
      # Setup Razorpay
      Razorpay.setup(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET)
      Razorpay.headers = { "Content-type" => "application/json" }

      # Fetch Razorpay order to get cart data from order notes
      razorpay_order = Razorpay::Order.fetch(razorpay_order_id)
      Rails.logger.info "Fetched Razorpay order: #{razorpay_order.inspect}"

      # Extract order data from order notes (Razorpay Entity uses @attributes; use .attributes to avoid method_missing arity error)
      order_notes = (razorpay_order.attributes || {})['notes'] || {}
      cart_data_json = order_notes['cart_data']
      shipping_address_json = order_notes['shipping_address']
      buyer_identity_json = order_notes['buyer_identity']
      return_url = order_notes['return_url']
      shipping_rate_details_json = order_notes['shipping_rate_details']

      # Parse JSON data
      cart_data = cart_data_json ? JSON.parse(cart_data_json) : nil
      shipping_address = shipping_address_json ? JSON.parse(shipping_address_json) : nil
      buyer_identity = buyer_identity_json ? JSON.parse(buyer_identity_json) : {}
      shipping_rate_details = shipping_rate_details_json ? JSON.parse(shipping_rate_details_json) : nil
      
      Rails.logger.info "PaymentVerifyService: Extracted shipping_rate_details_json: #{shipping_rate_details_json.inspect}"
      Rails.logger.info "PaymentVerifyService: Parsed shipping_rate_details: #{shipping_rate_details.inspect}"

      unless cart_data && shipping_address
        Rails.logger.error "Missing cart_data or shipping_address in order notes"
        return { error: "Missing order data", errors: ["Cart data or shipping address not found"] }
      end

      # Fetch payment details from Razorpay
      payment = Razorpay::Payment.fetch(razorpay_payment_id)
      Rails.logger.info "Fetched Razorpay payment: #{payment.inspect}"

      payment_attrs = payment.attributes || {}

      # Verify payment signature
      unless verify_signature(payment_attrs)
        Rails.logger.error "Payment signature verification failed"
        return { error: "Payment signature verification failed", errors: ["Invalid payment signature"] }
      end

      # Check if payment is successful
      payment_status = payment_attrs['status']
      unless payment_status == 'authorized' || payment_status == 'captured'
        Rails.logger.error "Payment not successful. Status: #{payment_status}"
        return { error: "Payment not successful", errors: ["Payment status: #{payment_status}"] }
      end

      # Create Shopify order (pass payment as hash to avoid Razorpay Entity [] arity issue)
      shop.init_session
      order_result = ShopifyServices::RazorpayOrderCreateService.call(
        shop,
        cart_data,
        shipping_address,
        buyer_identity,
        nil, # No COD fee for Razorpay orders
        payment_attrs,
        shipping_rate_details
      )

      if order_result[:error]
        Rails.logger.error "Failed to create Shopify order: #{order_result[:error]}"
        return order_result
      end

      # Fetch order details for order_status_url (redirect after success)
      order = ShopifyAPI::Order.find(order_result[:order_id])
      order_status_url = order.respond_to?(:order_status_url) ? order.order_status_url : nil

      {
        order_id: order_result[:order_id],
        order_number: order_result[:order_number],
        order_name: order_result[:order_name],
        total_price: order_result[:total_price],
        currency_code: order_result[:currency_code],
        order_status_url: order_status_url,
        payment_id: razorpay_payment_id,
        payment_amount: (payment_attrs['amount'].to_f / 100.0),
        payment_status: payment_status,
        return_url: return_url
      }
    rescue Razorpay::Error => e
      Rails.logger.error "Razorpay API error: #{e.message}"
      { error: "Razorpay API error: #{e.message}", errors: [e.message] }
    rescue StandardError => e
      Rails.logger.error "Error verifying Razorpay payment: #{e.message} #{e.backtrace.first(5).join("\n")}"
      { error: "Error verifying Razorpay payment: #{e.message}", errors: [e.message] }
    end

    private

    def verify_signature(payment_attrs)
      # Verify Razorpay signature (payment_attrs is hash from payment.attributes)
      # Signature format: razorpay_order_id + "|" + razorpay_payment_id
      message = "#{razorpay_order_id}|#{razorpay_payment_id}"
      
      expected_signature = OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new('sha256'),
        RAZORPAY_KEY_SECRET,
        message
      )

      secure_compare(expected_signature, razorpay_signature)
    end

    def secure_compare(a, b)
      return false unless a.length == b.length
      
      result = 0
      a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
      result == 0
    end
  end
end
