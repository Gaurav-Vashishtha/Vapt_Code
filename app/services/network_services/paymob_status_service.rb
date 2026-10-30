require 'net/http'
require 'uri'
require 'json'

module NetworkServices
  class PaymobStatusService < ApplicationService
    attr_reader :shop, :order_confirmation

    # Usage:
    # NetworkServices::PaymobStatusService.call(Shop.last, OrderConfirmation.first)

    def initialize(shop, order_confirmation)
      @shop = shop
      @order_confirmation = order_confirmation
    end

    def call
      return false if order_confirmation.blank?
      return false if @shop.setting.payment_provider_api_key.blank?

      order_ids = order_confirmation.phonepe_transaction_ids
      return false if order_ids.blank?

      token = fetch_auth_token
      return false if token.blank?

      order_ids.split(',').each do |order_id|
        status = check_transaction_status(token, order_id.strip)
        return true if status == true
      end

      false
    rescue => e
      SlackNotifyJob.perform_async(
        ":rage: (#{Rails.env})\n *Error* Paymob get Status for OrderConfirmation #{@order_confirmation.id} -> #{@shop.shopify_domain}\nError: #{e.message}"
      )
      false
    end

    private

    def fetch_auth_token
      uri = URI.parse("https://accept.paymob.com/api/auth/tokens")
      response = Net::HTTP.post(uri, {
        api_key: @shop.setting.payment_provider_api_key
      }.to_json, "Content-Type" => "application/json")

      result = JSON.parse(response.body)
      result["token"]
    rescue => e
      Rails.logger.error("Paymob auth token error: #{e.message}")
      nil
    end

    def check_transaction_status(token, order_id)
      uri = URI.parse("https://accept.paymob.com/api/ecommerce/orders/transaction_inquiry")
      request = Net::HTTP::Post.new(uri, {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{token}"
      })
      request.body = { order_id: order_id }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      return false unless response.is_a?(Net::HTTPSuccess)

      result = JSON.parse(response.body)
      result["success"] == true
    rescue JSON::ParserError
      false
    rescue => e
      Rails.logger.error("Paymob inquiry error for order_id #{order_id}: #{e.message}")
      false
    end
  end
end
