# frozen_string_literal: true

require "razorpay"

module RazorpayServices
  class OrderCreateService
    # POC: Hardcoded Razorpay credentials (test mode)
    RAZORPAY_KEY_ID = 'rzp_test_SHj8cWsiSU6T9c'
    RAZORPAY_KEY_SECRET = 'NALbfeh1E2rMrLvz23eC7LKV'

    attr_reader :shop, :cart_data, :shipping_address, :buyer_identity, :payment_amount, :selected_rule_id, :return_url, :shipping_rate_details

    def initialize(shop, cart_data, shipping_address, buyer_identity, payment_amount, selected_rule_id = nil, return_url = nil, shipping_rate_details = nil)
      @shop = shop
      @cart_data = cart_data
      @shipping_address = shipping_address
      @buyer_identity = buyer_identity
      @payment_amount = payment_amount
      @selected_rule_id = selected_rule_id
      @return_url = return_url
      @shipping_rate_details = shipping_rate_details
    end

    def self.call(shop, cart_data, shipping_address, buyer_identity, payment_amount, selected_rule_id = nil, return_url = nil, shipping_rate_details = nil)
      new(shop, cart_data, shipping_address, buyer_identity, payment_amount, selected_rule_id, return_url, shipping_rate_details).call
    end

    def call
      # Setup Razorpay
      Razorpay.setup(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET)
      Razorpay.headers = { "Content-type" => "application/json" }

      # Convert amount to paise (Razorpay expects amount in smallest currency unit)
      amount_in_paise = (payment_amount * 100).to_i

      # Prepare customer details
      customer_name = "#{shipping_address[:first_name] || shipping_address['first_name'] || ''} #{shipping_address[:last_name] || shipping_address['last_name'] || ''}".strip
      customer_email = buyer_identity[:email] || buyer_identity['email'] || ''
      customer_phone = buyer_identity[:phone] || buyer_identity['phone'] || ''

      # Create Razorpay order
      # Convert cart_data and addresses to JSON strings for storage in notes
      # Razorpay notes field accepts strings (max 256 chars each), so we store JSON strings
      cart_data_json = cart_data.is_a?(String) ? cart_data : cart_data.to_json
      shipping_address_json = shipping_address.is_a?(String) ? shipping_address : shipping_address.to_json
      buyer_identity_json = buyer_identity.is_a?(String) ? buyer_identity : buyer_identity.to_json

      # Build notes hash - Razorpay notes accepts string values (max 256 chars per value)
      notes_hash = {
        shop_domain: shop.shopify_domain.to_s,
        selected_rule_id: selected_rule_id.to_s,
        payment_type: 'partial_payment',
        cart_data: cart_data_json,
        shipping_address: shipping_address_json,
        buyer_identity: buyer_identity_json
      }
      notes_hash[:return_url] = return_url.to_s[0, 256] if return_url.present?
      
      Rails.logger.info "OrderCreateService: @shipping_rate_details present?: #{@shipping_rate_details.present?}"
      Rails.logger.info "OrderCreateService: @shipping_rate_details value: #{@shipping_rate_details.inspect}"
      
      if @shipping_rate_details.present?
        shipping_rate_json = @shipping_rate_details.is_a?(String) ? @shipping_rate_details : @shipping_rate_details.to_json
        notes_hash[:shipping_rate_details] = shipping_rate_json
        Rails.logger.info "OrderCreateService: Added shipping_rate_details to notes: #{shipping_rate_json}"
      else
        Rails.logger.warn "OrderCreateService: shipping_rate_details is NOT present, NOT adding to notes"
      end
      
      Rails.logger.info "OrderCreateService: Final notes_hash: #{notes_hash.keys.inspect}"

      # Add customer details if available
      if customer_name.present?
        notes_hash[:customer_name] = customer_name
      end
      if customer_email.present?
        notes_hash[:customer_email] = customer_email
      end
      if customer_phone.present?
        notes_hash[:customer_phone] = customer_phone
      end

      # Convert notes hash to use string keys (Razorpay API expects string keys)
      notes_hash_strings = notes_hash.transform_keys(&:to_s)
      
      order_params = {
        'amount' => amount_in_paise,
        'currency' => (cart_data[:currency_code] || cart_data['currency_code'] || 'INR').to_s,
        'receipt' => "receipt_#{Time.now.to_i}_#{SecureRandom.hex(4)}",
        'notes' => notes_hash_strings
      }

      Rails.logger.info "Creating Razorpay order with params: #{order_params.inspect}"

      # Razorpay::Order.create - use JSON string format like PaymentLink.create
      razorpay_order = Razorpay::Order.create(order_params.to_json)

      Rails.logger.info "Razorpay order created: #{razorpay_order.inspect}"

      # Access Razorpay::Order attributes from @attributes hash
      # The Razorpay gem stores response data in @attributes instance variable
      attributes = razorpay_order.instance_variable_get(:@attributes) || {}

      {
        razorpay_order_id: attributes['id'],
        amount: attributes['amount'],
        currency: attributes['currency'],
        order_data: attributes
      }
    rescue Razorpay::Error => e
      Rails.logger.error "Razorpay API error: #{e.message}"
      { error: "Razorpay API error: #{e.message}", errors: [e.message] }
    rescue StandardError => e
      Rails.logger.error "Error creating Razorpay order: #{e.message} #{e.backtrace.first(5).join("\n")}"
      { error: "Error creating Razorpay order: #{e.message}", errors: [e.message] }
    end
  end
end
