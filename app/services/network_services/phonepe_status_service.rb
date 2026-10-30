
module NetworkServices
  class PhonepeStatusService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation
    attr_reader :test
    #NetworkServices::PhonepeStatusService.call(Shop.last,OrderConfirmation.last,true)

    def initialize(shop, order_confirmation, test=false)
      @shop = shop
      @order_confirmation = order_confirmation
      @test = test
    end

    def call
      begin
        if !order_confirmation.blank? 
          merchantId = @test?"JAGSTOREONLINE": @shop.setting.payment_provider_api_key #
          api_salt_key = @test?"51c0e3e1-8ebc-48c2-a319-a29d95847441": @shop.setting.payment_provider_api_secret.split(":")[0] #
          salt_index = @test? "1" : @shop.setting.payment_provider_api_secret.split(":")[1] #"1"
          if salt_index.blank?
            salt_index = "1"
          end

          # Get all transaction IDs from the order.
          transactionIds = order_confirmation.phonepe_transaction_ids

          transactionIds.split(',').each do|transactionId|
            hash   = Digest::SHA256.hexdigest("/pg/v1/status/#{merchantId}/#{transactionId}#{api_salt_key}")
            x_verify=	"#{hash}####{salt_index}"
            uri = URI.parse("https://api.phonepe.com/apis/hermes/pg/v1/status/#{merchantId}/#{transactionId}")
            request = Net::HTTP::Get.new(uri)
            request.content_type = "application/json"
            request["X-Merchant-Id"] = merchantId
            request["X-Verify"] = x_verify
            req_options = {
              use_ssl: uri.scheme == "https",
            }
            response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
              http.request(request)
            end
            resp_hash = JSON.parse(response.body)
            puts resp_hash
            if resp_hash.dig('success') && resp_hash.dig('code')=='PAYMENT_SUCCESS'
              return true
            end
          end
        end  
        return false
      rescue Exception => e 
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n *Error* PhonePe get Status #{@order_confirmation.id} -> #{@shop.shopify_domain} error: #{e.message}"
        )
        return false
      end
    end
  end
end