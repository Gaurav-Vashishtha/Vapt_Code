require 'net/http'
require 'uri'
require 'json'
require 'base64'

module NetworkServices
  class GeideaLinkService < ApplicationService
    attr_reader :shop, :order_confirmation

    # Usage:
    # NetworkServices::GeideaLinkService.call(Shop.last, OrderConfirmation.first)

    def initialize(shop, order_confirmation)
      @shop = shop
      @order_confirmation = order_confirmation
    end

    def call
      return if order_confirmation.blank?
      if order_confirmation.prepaid_link.present?
        return order_confirmation.prepaid_link
      end
      return if @shop.setting.payment_provider_api_key.blank? || @shop.setting.payment_provider_api_secret.blank?

      digest = Digest::MD5.hexdigest(@order_confirmation.id.to_s)
      order_confirmation.update(digest: digest)

      amount = ShopifyServices::PrepaidOrderService.new(nil, order_confirmation.shop, order_confirmation.id).get_total_amount
      
      payment_link = create_geidea_link(amount)
      return unless payment_link

      cutly_url = NetworkServices::CutlyLinkService.call(payment_link)
      order_confirmation.update(prepaid_link: cutly_url)
      
      cutly_url
    end

    private

    def create_geidea_link(amount)
      uri = URI("https://api.merchant.geidea.net/payment-intent/api/v1/direct/eInvoice")
      
      # Extract phone number and country code
      phone_number = extract_phone_number
      phone_country_code = extract_country_code
      
      # Get customer email or use default
      customer_email = @order_confirmation.customer_email.presence || "customer@example.com"
      
      # Prepare request body
      request_body = {
        amount: amount,
        currency: @order_confirmation.currency || "EGP",
        customer: {
          name: @order_confirmation.customer_name || "Customer",
          email: customer_email,
          phoneCountryCode: phone_country_code,
          phoneNumber: phone_number
        },
        eInvoiceDetails: {
          subtotal: amount,
          grandTotal: amount,
          extraChargesType: "Amount",
          invoiceDiscountType: "Amount",
          eInvoiceItems: [
            {
              description: "Order #{@order_confirmation.order_number || @order_confirmation.order_id}",
              price: amount,
              quantity: 1,
              itemDiscountType: "Amount",
              taxType: "Amount",
              total: amount
            }
          ],
          merchantReferenceId: @order_confirmation.order_id.to_s,
          callbackUrl: "https://#{ENV.fetch("APP_HOST", nil)}/order/prepaid?digest=#{@order_confirmation.digest}",
          type: "Detailed",
          language: "EN"
        }
      }
      
      # Create Basic Auth header
      credentials = "#{@shop.setting.payment_provider_api_key}:#{@shop.setting.payment_provider_api_secret}"
      auth_header = "Basic #{Base64.strict_encode64(credentials)}"
      
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        req = Net::HTTP::Post.new(uri.path, {
          "Content-Type" => "application/json",
          "Authorization" => auth_header,
          "Accept" => "application/json"
        })
        req.body = request_body.to_json
        http.request(req)
      end
      
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("Geidea API error: HTTP #{response.code} - #{response.message}")
        Rails.logger.error("Response body: #{response.body}")
        return nil
      end
      
      result = JSON.parse(response.body)
      
      if result["responseCode"] == "000" && result.dig("paymentIntent", "link")
        payment_link = result.dig("paymentIntent", "link")
        # Store the 'number' field (not UUID) for status checking
        # The API uses 'number' as the paymentIntentId header value
        payment_number = result.dig("paymentIntent", "number")
        
        # Store payment number for status checking
        order_confirmation.update(phonepe_transaction_ids: payment_number)
        order_confirmation.update(prepaid_status: 'CALLBACK-RECEIVED')
        
        payment_link
      else
        error_message = result['responseMessage'] || result['detailedResponseMessage'] || 'Unknown error'
        Rails.logger.error("Geidea link creation error: #{error_message}")
        Rails.logger.error("Response code: #{result['responseCode']}")
        Rails.logger.error("Full response: #{result.inspect}")
        nil
      end
    rescue => e
      Rails.logger.error("Geidea link creation exception: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    def extract_phone_number
      phone = @order_confirmation.customer_number || ""
      country_code = @order_confirmation.country_code || "EG"
      
      # Clean phone number - remove all non-digit characters except +
      cleaned_phone = phone.gsub(/[^\d+]/, '')
      
      # Use Phonelib to parse the phone number properly
      parsed = Phonelib.parse(cleaned_phone, country_code)
      
      if parsed.valid? && parsed.country_code.present?
        # Extract the full national number (area code + local number)
        # This gives us the number without the country code prefix
        national = parsed.national(false) # Returns digits without formatting
        
        # Remove any remaining non-digit characters
        national = national.gsub(/[^\d]/, '')
        
        # If national format still includes country code, strip it
        country_code_str = parsed.country_code.to_s
        if national.start_with?(country_code_str) && national.length > country_code_str.length
          national = national[country_code_str.length..-1]
        end
        
        national.presence || cleaned_phone.gsub(/^\+\d{1,3}/, '').gsub(/[^\d]/, '')
      else
        # Fallback: manually extract phone number by removing country code
        cleaned = cleaned_phone.gsub(/[^\d]/, '')
        
        # Map of country codes to their numeric prefix
        country_code_map = {
          "EG" => "20",
          "SA" => "966",
          "AE" => "971",
          "KW" => "965",
          "QA" => "974",
          "BH" => "973",
          "OM" => "968",
          "JO" => "962",
          "LB" => "961",
          "IQ" => "964"
        }
        
        code_prefix = country_code_map[country_code.upcase] || "20"
        
        # If the cleaned number starts with country code, remove it
        if cleaned.start_with?(code_prefix) && cleaned.length > code_prefix.length
          cleaned = cleaned[code_prefix.length..-1]
        end
        
        # Final fallback: just return last 10 digits or the whole number if shorter
        cleaned.length > 10 ? cleaned[-10..-1] : cleaned
      end
    rescue => e
      Rails.logger.error("Error extracting phone number: #{e.message}")
      Rails.logger.error("Phone: #{phone}, Country: #{country_code}")
      # Final fallback - return last 10 digits or all digits
      phone.gsub(/[^\d]/, '').tap do |digits|
        return digits.length > 10 ? digits[-10..-1] : digits
      end
    end

    def extract_country_code
      country_code = @order_confirmation.country_code || "EG"
      
      # Map country codes to phone country codes
      phone_codes = {
        "EG" => "+20",
        "SA" => "+966",
        "AE" => "+971",
        "KW" => "+965",
        "QA" => "+974",
        "BH" => "+973",
        "OM" => "+968",
        "JO" => "+962",
        "LB" => "+961",
        "IQ" => "+964"
      }
      
      phone_code = phone_codes[country_code.upcase] || "+20" # Default to Egypt
      
      # Try to parse phone number to get actual country code if available
      phone = @order_confirmation.customer_number
      if phone.present?
        begin
          parsed = Phonelib.parse(phone, country_code)
          if parsed.valid? && parsed.country_code.present?
            phone_code = "+#{parsed.country_code}"
          end
        rescue => e
          Rails.logger.error("Error parsing phone for country code: #{e.message}")
        end
      end
      
      phone_code
    rescue => e
      Rails.logger.error("Error extracting country code: #{e.message}")
      "+20"
    end
  end
end

