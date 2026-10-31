require "razorpay"
module NetworkServices
  class WhatsappPrepaidZenithService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation

    #resp = NetworkServices::WhatsappPrepaidZenithService.call(Shop.first,OrderConfirmation.last)

    def initialize(shop, order_confirmation)
      @shop = shop
      @order_confirmation = order_confirmation
    end

    def call
      if !@order_confirmation.blank? && @order_confirmation.country_code=='IN'
        
        resp = HTTParty.post('https://graph.facebook.com/v15.0/105755458857534/messages',
          body: { 
            messaging_product: "whatsapp", 
            to: @order_confirmation.customer_number, 
            type: "template", 
                template: {
                  name: 'converttoprepaidtwo',
                    language: {
                        code: "en_US"
                    },
                    components: [
                      {
                        type: "button",
                        sub_type: "url",
                        index: "0", 
                        parameters: [
                            {
                                type: "text",
                                text: @order_confirmation.prepaid_link.gsub('https://rzp.io/i/','')
                            }
                        ]
                    }
                        
                    ]
                }
            },
          headers: {
            'Content-Type' => 'application/json',
            'Authorization' => ENV.fetch("WHATSAPP_BEARER_TOKEN", nil)
          },
        )
        resp_hash = resp.to_h
        if !resp_hash.blank?
          TwilioLog.create(
            sid: resp_hash['messages'] && resp_hash['messages'].first['id'] ? resp_hash['messages'].first['id']:'' ,
            ver_type: 'WHATSAPP',
            country_code: @order_confirmation.country_code,
            customer_number: @order_confirmation.customer_number,
            status: resp_hash['messages'] && resp_hash['messages'].first['id'] ? 'SUCCESS' : resp_hash.to_s,
            order_confirmation: @order_confirmation,
            shop: shop
          )
        end
        resp
      end
    end
  end
end