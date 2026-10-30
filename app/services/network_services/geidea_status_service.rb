require 'net/http'
require 'uri'
require 'json'
require 'base64'

module NetworkServices
  class GeideaStatusService < ApplicationService
    attr_reader :shop, :order_confirmation

    # Usage:
    # NetworkServices::GeideaStatusService.call(Shop.last, OrderConfirmation.first)

    def initialize(shop, order_confirmation)
      @shop = shop
      @order_confirmation = order_confirmation
    end

    def call
      return false if order_confirmation.blank?
      return false if @shop.setting.payment_provider_api_key.blank? || @shop.setting.payment_provider_api_secret.blank?

      payment_intent_id = order_confirmation.phonepe_transaction_ids
      return false if payment_intent_id.blank?

      status = check_payment_status(payment_intent_id)
      status
    rescue => e
      SlackNotifyJob.perform_async(
        ":rage: (#{Rails.env})\n *Error* Geidea get Status for OrderConfirmation #{@order_confirmation.id} -> #{@shop.shopify_domain}\nError: #{e.message}"
      )
      false
    end

    private

    def check_payment_status(payment_intent_id)
      uri = URI("https://api.merchant.geidea.net/pgw/api/v1/direct/order")
      
      # Create Basic Auth header
      credentials = "#{@shop.setting.payment_provider_api_key}:#{@shop.setting.payment_provider_api_secret}"
      auth_header = "Basic #{Base64.strict_encode64(credentials)}"
      
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        req = Net::HTTP::Get.new(uri.path)
        req["paymentIntentId"] = payment_intent_id
        req["Authorization"] = auth_header
        req["Accept"] = "application/json"
        http.request(req)
      end

      return false unless response.is_a?(Net::HTTPSuccess)

      result = JSON.parse(response.body)
      
      # Check if payment is successful
      if result["responseCode"] == "000" && result.dig("order", "detailedStatus") == "Paid"
        true
      else
        false
      end
    rescue JSON::ParserError
      false
    rescue => e
      Rails.logger.error("Geidea inquiry error for payment_intent_id #{payment_intent_id}: #{e.message}")
      false
    end
  end
end

