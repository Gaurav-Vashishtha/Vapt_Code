require 'net/http'
require 'uri'
require 'json'

module NetworkServices
  class PaymobLinkService < ApplicationService
    attr_reader :shop, :order_confirmation

    # Usage:
    # NetworkServices::PaymobLinkService.call(Shop.last, OrderConfirmation.first)

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

      token = fetch_auth_token
      return unless token

      amount_cents = ((ShopifyServices::PrepaidOrderService.new(nil, order_confirmation.shop, order_confirmation.id).get_total_amount) * 100).to_i

      payment_link = create_paymob_link(token, amount_cents)
      return unless payment_link

      cutly_url = NetworkServices::CutlyLinkService.call(payment_link)
      order_confirmation.update(prepaid_link: cutly_url)
      
      cutly_url
    end

    private

    def fetch_auth_token
      uri = URI("https://accept.paymob.com/api/auth/tokens")
      response = Net::HTTP.post(uri, {
        api_key: @shop.setting.payment_provider_api_key
      }.to_json, "Content-Type" => "application/json")

      result = JSON.parse(response.body)
      result["token"]
    rescue => e
      Rails.logger.error("Paymob auth error: #{e.message}")
      nil
    end

    require 'time' # for iso8601 formatting
    def create_paymob_link(token, amount_cents)
      uri = URI("https://accept.paymob.com/api/ecommerce/payment-links")
    
      expiry_minutes = @shop.setting.prepaid_expiry.to_i
      expiry_time = (Time.now + expiry_minutes.minutes).iso8601
    
      request_body = {
        amount_cents: amount_cents,
        reference_id: @order_confirmation.order_id,
        payment_methods: @shop.setting.payment_provider_api_secret.split(',').map(&:strip).map(&:to_i),
        redirection_url: "https://#{ENV['APP_HOST']}/order/prepaid?digest=#{@order_confirmation.digest}",
        save_selection: true,
        is_live: true,
        expires_at: expiry_time
      }
    
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        req = Net::HTTP::Post.new(uri.path, {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{token}"
        })
        req.body = request_body.to_json
        http.request(req)
      end
    
      result = JSON.parse(response.body)
      order_confirmation.update(phonepe_transaction_ids: result["order"])
      order_confirmation.update(prepaid_status: 'CALLBACK-RECEIVED')
      result["shorten_url"]
    rescue => e
      Rails.logger.error("Paymob link creation error: #{e.message}")
      nil
    end
    
  end
end
