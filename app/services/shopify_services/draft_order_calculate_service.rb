# frozen_string_literal: true

module ShopifyServices
  class DraftOrderCalculateService
    attr_reader :shop, :cart_data, :shipping_address

    def initialize(shop, cart_data, shipping_address)
      @shop = shop
      @cart_data = cart_data
      @shipping_address = shipping_address
      @client = nil
    end

    def self.call(shop, cart_data, shipping_address)
      new(shop, cart_data, shipping_address).call
    end

    def call
      shop.init_session
      @client = ShopifyAPI::GraphQL.client

      # Calculate draft order taxes
      calculate_response = calculate_draft_order

      if calculate_response&.data&.draft_order_calculate&.user_errors&.any?
        errors = calculate_response.data.draft_order_calculate.user_errors
        error_messages = errors.map { |e| "#{e.field}: #{e.message}" }.join(", ")
        Rails.logger.error "Error calculating draft order: #{error_messages}"
        return { error: "Error calculating draft order", errors: errors }
      end

      calculated_order = calculate_response&.data&.draft_order_calculate&.calculated_draft_order
      unless calculated_order
        Rails.logger.error "Failed to calculate draft order: #{calculate_response.inspect}"
        return { error: "Failed to calculate draft order" }
      end

      # Extract tax information
      tax_lines = calculated_order.tax_lines || []
      tax_details = tax_lines.map do |tax_line|
        # price might be a scalar (decimal) or MoneyV2 object
        price_amount = if tax_line.price.respond_to?(:amount)
          tax_line.price.amount
        else
          tax_line.price
        end
        price_amount = price_amount.to_f if price_amount.is_a?(String)
        price_amount ||= 0
        
        {
          title: tax_line.title,
          price: price_amount,
          rate: tax_line.rate
        }
      end

      # Extract shipping rates if available
      shipping_rates = calculated_order.available_shipping_rates || []
      shipping_details = shipping_rates.map do |rate|
        # price is MoneyV2 object with amount
        # According to user: shipping cost response is in rupees (not paise)
        # So ₹100 = 100.0 (already in rupees), NOT 10000 paise
        # Use it directly without conversion
        price_amount = rate.price&.amount || 0
        price_amount = price_amount.to_f if price_amount.is_a?(String)
        
        Rails.logger.info "Shipping rate #{rate.title}: raw price_amount from Shopify = #{price_amount}"
        
        # User confirmed: availableShippingRates.price.amount is already in rupees
        # Use directly - no conversion needed
        price_in_rupees = price_amount
        
        Rails.logger.info "Shipping rate #{rate.title}: price in rupees = #{price_in_rupees}"
        
        {
          handle: rate.handle,
          title: rate.title,
          price: price_in_rupees
        }
      end

      # Extract money values (scalar decimals)
      total_tax_amount = calculated_order.total_tax || 0
      total_tax_amount = total_tax_amount.to_f if total_tax_amount.is_a?(String)
      
      subtotal_price_amount = calculated_order.subtotal_price || 0
      subtotal_price_amount = subtotal_price_amount.to_f if subtotal_price_amount.is_a?(String)
      
      total_price_amount = calculated_order.total_price || 0
      total_price_amount = total_price_amount.to_f if total_price_amount.is_a?(String)

      {
        success: true,
        total_tax: total_tax_amount,
        subtotal_price: subtotal_price_amount,
        total_price: total_price_amount,
        tax_lines: tax_details,
        available_shipping_rates: shipping_details
      }
    rescue StandardError => e
      Rails.logger.error "Error in DraftOrderCalculateService: #{e.message} #{e.backtrace.first(5).join("\n")}"
      { error: e.message }
    end

    private

    def calculate_draft_order
      query = @client.parse <<-'GRAPHQL'
        mutation ($input: DraftOrderInput!) {
          draftOrderCalculate(input: $input) {
            calculatedDraftOrder {
              totalTax
              subtotalPrice
              totalPrice
              taxLines {
                title
                price
                rate
              }
              availableShippingRates {
                handle
                title
                price {
                  amount
                }
              }
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      variables = {
        input: {
          lineItems: build_line_items,
          shippingAddress: build_shipping_address
        }
      }

      # Add email if available
      if @cart_data[:email] || @cart_data['email']
        variables[:input][:email] = @cart_data[:email] || @cart_data['email']
      end

      # Add applied discount if present
      applied_discount = build_applied_discount
      variables[:input][:appliedDiscount] = applied_discount if applied_discount.present?

      Rails.logger.info "Calculating draft order taxes with variables: #{variables.inspect}"
      resp = @client.query(query, variables: variables)
      Rails.logger.info "Draft order calculate response: #{resp.inspect}"
      resp
    end

    def build_line_items
      items = @cart_data[:items] || @cart_data['items'] || []
      items.map do |item|
        variant_id = item[:variant_id] || item['variant_id'] || item[:id] || item['id']
        quantity = item[:quantity] || item['quantity'] || 1

        line_item = {
          variantId: "gid://shopify/ProductVariant/#{variant_id}",
          quantity: quantity.to_i
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
        firstName: @shipping_address[:first_name] || @shipping_address['first_name'] || '',
        lastName: @shipping_address[:last_name] || @shipping_address['last_name'] || '',
        address1: @shipping_address[:address1] || @shipping_address['address1'] || '',
        address2: @shipping_address[:address2] || @shipping_address['address2'] || '',
        city: @shipping_address[:city] || @shipping_address['city'] || '',
        province: @shipping_address[:province] || @shipping_address['province'] || @shipping_address[:state] || @shipping_address['state'] || '',
        zip: @shipping_address[:zip] || @shipping_address['zip'] || @shipping_address[:postal_code] || @shipping_address['postal_code'] || '',
        country: @shipping_address[:country] || @shipping_address['country'] || ''
      }
    end

    def build_applied_discount
      # Extract order-level discounts from cart
      discount_applications = @cart_data[:cart_level_discount_applications] || @cart_data['cart_level_discount_applications'] || []
      return nil if discount_applications.empty?

      # Use the first order-level discount
      discount = discount_applications.first
      discount_type = discount[:type] || discount['type']
      discount_value = discount[:value] || discount['value']
      discount_title = discount[:title] || discount['title'] || discount[:description] || discount['description'] || 'Discount'

      currency_code = @cart_data[:currency_code] || @cart_data['currency_code'] || 'USD'

      if discount_type == 'percentage' || discount_value.to_s.include?('%')
        percentage = discount_value.to_f
        percentage = percentage / 100.0 if percentage > 1
        {
          valueType: 'PERCENTAGE',
          value: (percentage * 100).round(2),
          title: discount_title,
          description: discount_title
        }
      else
        # Fixed amount discount
        discount_amount = discount_value.to_f
        discount_amount = discount_amount / 100.0 if discount_amount > 100 # Assume cents if > 100
        {
          valueType: 'FIXED_AMOUNT',
          value: discount_amount.round(2),
          title: discount_title,
          description: discount_title
        }
      end
    end
  end
end
