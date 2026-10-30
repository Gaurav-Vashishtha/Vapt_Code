# frozen_string_literal: true

module ShopifyServices
  class RazorpayOrderCreateService
    attr_reader :shop, :cart_data, :shipping_address, :buyer_identity, :cod_fee, :razorpay_payment, :shipping_rate_details

    def initialize(shop, cart_data, shipping_address, buyer_identity, cod_fee = nil, razorpay_payment = nil, shipping_rate_details = nil)
      @shop = shop
      @cart_data = cart_data
      @shipping_address = shipping_address
      @buyer_identity = buyer_identity
      @cod_fee = cod_fee
      @razorpay_payment = razorpay_payment
      @shipping_rate_details = shipping_rate_details
      @client = nil
      
      Rails.logger.info "RazorpayOrderCreateService initialized with shipping_rate_details: #{@shipping_rate_details.inspect}"
      Rails.logger.info "shipping_rate_details class: #{@shipping_rate_details.class}"
      Rails.logger.info "shipping_rate_details present?: #{@shipping_rate_details.present?}"
    end

    def self.call(shop, cart_data, shipping_address, buyer_identity, cod_fee = nil, razorpay_payment = nil, shipping_rate_details = nil)
      new(shop, cart_data, shipping_address, buyer_identity, cod_fee, razorpay_payment, shipping_rate_details).call
    end

    def call
      shop.init_session
      @client = ShopifyAPI::GraphQL.client

      # Create draft order
      draft_order_response = create_draft_order

      if draft_order_response&.data&.draft_order_create&.user_errors&.any?
        errors = draft_order_response.data.draft_order_create.user_errors
        error_messages = errors.map { |e| "#{e.field}: #{e.message}" }.join(", ")
        Rails.logger.error "Error creating draft order: #{error_messages}"
        return { error: "Error creating draft order", errors: errors }
      end

      unless draft_order_response&.data&.draft_order_create&.draft_order
        Rails.logger.error "Failed to create draft order: #{draft_order_response.inspect}"
        return { error: "Failed to create draft order" }
      end

      # Complete draft order to create real order (payment already captured via Razorpay)
      order_id = create_order_from_draft_order(draft_order_response)

      unless order_id
        Rails.logger.error "Failed to create order from draft order"
        return { error: "Failed to create order from draft order" }
      end

      # Fetch order details
      order = ShopifyAPI::Order.find(order_id)
      
      {
        success: true,
        order_id: order_id,
        order_number: order.order_number,
        order_name: order.name,
        total_price: order.total_price,
        currency_code: order.currency
      }
    rescue StandardError => e
      Rails.logger.error "Error in RazorpayOrderCreateService: #{e.message} #{e.backtrace.first(5).join("\n")}"
      { error: e.message }
    end

    private

    def create_draft_order
      query = @client.parse <<-'GRAPHQL'
        mutation ($input: DraftOrderInput!) {
          draftOrderCreate(input: $input) {
            draftOrder {
              id
              invoiceUrl
              totalPrice
              status
              name
              currencyCode
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      # Format phone number to E.164 format (required by Shopify)
      formatted_phone = format_phone_number(buyer_identity[:phone] || buyer_identity['phone'])

      # Build note with payment information
      note = "Order created via Razorpay payment"
      if razorpay_payment
        note += "\nRazorpay Payment ID: #{razorpay_payment['id']}"
        note += "\nPayment Status: #{razorpay_payment['status']}"
        note += "\nPayment Method: #{razorpay_payment['method']}" if razorpay_payment['method']
      end

      variables = {
        input: {
          lineItems: build_line_items,
          shippingAddress: build_shipping_address,
          billingAddress: build_shipping_address,
          email: buyer_identity[:email] || buyer_identity['email'] || nil,
          phone: formatted_phone,
          note: note,
          tags: ["Razorpay", "Created-From-COD-King"],
          taxExempt: false,
          appliedDiscount: build_applied_discount
        }
      }

      # Add shipping line with COD fee if present (shouldn't be for Razorpay, but keeping for consistency)
      shipping_line = build_shipping_line
      Rails.logger.info "Shipping line result: #{shipping_line.inspect}"
      if shipping_line.present?
        variables[:input][:shippingLine] = shipping_line
        Rails.logger.info "Added shippingLine to GraphQL variables: #{variables[:input][:shippingLine].inspect}"
      else
        Rails.logger.warn "Shipping line is nil or empty, NOT adding to GraphQL variables"
      end

      # Add customer if we have email/phone to match existing customer
      if buyer_identity[:email].present? || buyer_identity[:phone].present?
        customer_id = find_or_create_customer
        variables[:input][:customerId] = customer_id if customer_id.present?
      end

      Rails.logger.info "Creating Razorpay draft order with variables: #{variables.inspect}"
      resp = @client.query(query, variables: variables)
      Rails.logger.info "Draft order response: #{resp.inspect}"
      resp
    end

    def build_line_items
      items = cart_data[:items] || cart_data['items'] || []
      items.map do |item|
        variant_id = item[:variant_id] || item['variant_id'] || item[:id] || item['id']
        quantity = item[:quantity] || item['quantity'] || 1

        line_item = {
          variantId: "gid://shopify/ProductVariant/#{variant_id}",
          quantity: quantity
        }

        # Apply line item discounts if present
        if item[:line_level_discount_allocations] || item['line_level_discount_allocations']
          discounts = item[:line_level_discount_allocations] || item['line_level_discount_allocations']
          total_discount_cents = discounts.sum { |d| d[:amount] || d['amount'] || 0 }

          if total_discount_cents > 0
            total_discount_amount = (total_discount_cents / 100.0).to_f
            per_unit_discount = quantity.to_i > 0 ? (total_discount_amount / quantity.to_f) : total_discount_amount

            discount_title = discounts.first&.dig(:discount_application, :title) ||
                           discounts.first&.dig('discount_application', 'title') ||
                           discounts.first&.dig(:discount_application, :description) ||
                           discounts.first&.dig('discount_application', 'description') ||
                           'Discount'

            line_item[:appliedDiscount] = {
              valueType: 'FIXED_AMOUNT',
              value: per_unit_discount.round(2),
              title: discount_title,
              description: discount_title
            }
          end
        end

        line_item
      end
    end

    def build_shipping_address
      {
        firstName: shipping_address[:first_name] || shipping_address['first_name'] || '',
        lastName: shipping_address[:last_name] || shipping_address['last_name'] || '',
        address1: shipping_address[:address1] || shipping_address['address1'] || '',
        address2: shipping_address[:address2] || shipping_address['address2'] || '',
        city: shipping_address[:city] || shipping_address['city'] || '',
        province: shipping_address[:province] || shipping_address['province'] || '',
        zip: shipping_address[:zip] || shipping_address['zip'] || '',
        country: shipping_address[:country] || shipping_address['country'] || 'India'
      }
    end

    def build_applied_discount
      discount_applications = cart_data[:cart_level_discount_applications] || cart_data['cart_level_discount_applications'] || []
      return nil if discount_applications.empty?

      allocated_cents = discount_applications.sum do |d|
        (d[:total_allocated_amount] || d['total_allocated_amount']).to_f
      end
      titles = discount_applications.filter_map { |d| d[:title] || d['title'] || d[:description] || d['description'] }
      discount_title = titles.uniq.join(', ').presence || 'Discount'

      if allocated_cents.positive?
        return {
          valueType: 'FIXED_AMOUNT',
          value: (allocated_cents / 100.0).round(2),
          description: discount_title
        }
      end

      discount = discount_applications.first
      value_type = discount[:value_type] || discount['value_type']
      value = (discount[:value] || discount['value']).to_f

      if value_type == 'percentage'
        { valueType: 'PERCENTAGE', value: value.round(2), description: discount_title }
      else
        { valueType: 'FIXED_AMOUNT', value: value.round(2), description: discount_title }
      end
    end

    def build_shipping_line
      Rails.logger.info "Building shipping line. shipping_rate_details present?: #{@shipping_rate_details.present?}"
      Rails.logger.info "shipping_rate_details value: #{@shipping_rate_details.inspect}"
      
      # Use shipping rate details if provided (from draftOrderCalculate)
      if @shipping_rate_details.present?
        shipping_details = if @shipping_rate_details.is_a?(Hash)
          @shipping_rate_details
        elsif @shipping_rate_details.is_a?(String)
          JSON.parse(@shipping_rate_details) rescue {}
        else
          {}
        end
        
        Rails.logger.info "Parsed shipping_details: #{shipping_details.inspect}"
        Rails.logger.info "shipping_details keys: #{shipping_details.keys.inspect}" if shipping_details.is_a?(Hash)
        
        # Handle both string and symbol keys
        shipping_price = shipping_details['price'] || shipping_details[:price] || 0
        shipping_title = shipping_details['title'] || shipping_details[:title] || 'Shipping'
        
        Rails.logger.info "Extracted shipping_price: #{shipping_price}, shipping_title: #{shipping_title}"
        currency_code = cart_data[:currency_code] || cart_data['currency_code'] || 'INR'
        
        Rails.logger.info "Shipping price: #{shipping_price}, title: #{shipping_title}, currency: #{currency_code}"
        
        # Shopify's priceWithCurrency.amount expects decimal value in rupees (e.g., 100.0 for ₹100)
        # The price from draftOrderCalculate is already in rupees
        price_amount = shipping_price.to_f
        
        shipping_line = {
          priceWithCurrency: {
            amount: price_amount.to_s,
            currencyCode: currency_code
          },
          title: shipping_title
        }
        
        Rails.logger.info "Built shipping_line: #{shipping_line.inspect}"
        return shipping_line
      end
      
      Rails.logger.warn "No shipping_rate_details provided, skipping shipping line"

      # Fallback: Add COD fee as shipping charge if present (shouldn't happen for Razorpay orders)
      return nil unless cod_fee.present? && cod_fee.to_f > 0

      currency_code = cart_data[:currency_code] || cart_data['currency_code'] || 'USD'
      cod_fee_amount = cod_fee.to_f

      {
        priceWithCurrency: {
          amount: cod_fee_amount,
          currencyCode: currency_code
        },
        title: 'COD Fee'
      }
    end

    def format_phone_number(phone)
      return nil unless phone.present?
      
      cleaned = phone.to_s.gsub(/[^\d+]/, '')
      
      if cleaned.present? && !cleaned.start_with?('+')
        cleaned = "+#{cleaned}"
      end
      
      cleaned.presence
    end

    def find_or_create_customer
      nil
    end

    def create_order_from_draft_order(draft_order_response)
      draft_order_id = draft_order_response.data.draft_order_create.draft_order.id
      draft_order_numeric_id = draft_order_id.gsub('gid://shopify/DraftOrder/', '')
      
      shop.init_session
      draft_order = ShopifyAPI::DraftOrder.find(draft_order_numeric_id)

      # For Razorpay orders, payment is already captured, so payment_pending is false
      if draft_order.complete(payment_pending: false)
        Rails.logger.info "Successfully created Razorpay order: #{draft_order.order_id}"
        return draft_order.order_id
      else
        Rails.logger.error "Failed to complete draft order: #{draft_order.errors.full_messages.join(', ')}"
        return nil
      end
    rescue StandardError => e
      Rails.logger.error "Error completing draft order: #{e.message}"
      nil
    end
  end
end
