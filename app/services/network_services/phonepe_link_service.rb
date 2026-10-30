
module NetworkServices
  class PhonepeLinkService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation
    attr_reader :test
    #NetworkServices::PhonepeLinkService.call(Shop.last,OrderConfirmation.last,true)

    def initialize(shop, order_confirmation, test=false)
      @shop = shop
      @order_confirmation = order_confirmation
      @test = test
    end

    def attach_merchant_transaction_id_to_order(order_confirmation,merchantTransactionId)
      transactionIds = ''
      if order_confirmation.phonepe_transaction_ids.blank?
        transactionIds = merchantTransactionId
      else
        transactionIds = order_confirmation.phonepe_transaction_ids + "," + merchantTransactionId
      end
      return order_confirmation.update(phonepe_transaction_ids:transactionIds)
    end


    def call
      if !order_confirmation.blank? 
        uri = URI.parse("https://api.phonepe.com/apis/hermes/pg/v1/pay")
        link= "/pg/v1/pay"

        digest = Digest::MD5.hexdigest(@order_confirmation.id.to_s)
        order_confirmation.update(digest: digest)
        
        merchantTransactionId=SecureRandom.uuid  
        

        merchantId = @test?"JAGSTOREONLINE": @shop.setting.payment_provider_api_key #
        api_salt_key = @test?"51c0e3e1-8ebc-48c2-a319-a29d95847441": @shop.setting.payment_provider_api_secret.split(":")[0] #
        salt_index = @test? "1" : @shop.setting.payment_provider_api_secret.split(":")[1] #"1"
        if salt_index.blank?
          salt_index="1"
        end

        order_amount = ((ShopifyServices::PrepaidOrderService.new(nil,order_confirmation.shop, order_confirmation.id).get_total_amount)*100).to_i
        redirectUrl = "https://#{ENV['APP_HOST']}/order/prepaid?digest=#{digest}",
    
        json =  "{\"merchantId\": \"#{merchantId}\",
                  \"merchantTransactionId\": \"#{merchantTransactionId}\", 
                  \"merchantUserId\": \"MUID123\", 
                  \"amount\": #{order_amount}, 
                  \"redirectUrl\": \"#{redirectUrl}\",
                  \"redirectMode\": \"REDIRECT\",
                  \"mobileNumber\": \"#{order_confirmation.customer_number}\",
                  \"paymentInstrument\": 
                  {\"type\": \"PAY_PAGE\"}
                  }"

      base_64_payload = Base64.strict_encode64 json
      hash   = Digest::SHA256.hexdigest("#{base_64_payload}#{link}#{api_salt_key}")
      x_verify=	"#{hash}####{salt_index}"
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request["X-Verify"] = x_verify
      request.body = JSON.dump({
        "request" => base_64_payload
      })
      
      req_options = {
        use_ssl: uri.scheme == "https",
      }
        
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
      resp_hash = JSON.parse(response.body)
      if !resp_hash.dig('data','instrumentResponse','redirectInfo','url').blank?
        payment_link = resp_hash.dig('data','instrumentResponse','redirectInfo','url')
        short_url = NetworkServices::CutlyLinkService.call(payment_link)
        order_confirmation.update(prepaid_link: short_url)
        attach_merchant_transaction_id_to_order(order_confirmation,merchantTransactionId)
      else
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Unable to create payment link for PhonePe for shop for order confirmation #{order_confirmation.id} shop #{order_confirmation.shop.shopify_domain} #{resp_hash.to_s}"
        )
      end      
      puts response.body
      order_confirmation.prepaid_link
      end  
    end
  end
end