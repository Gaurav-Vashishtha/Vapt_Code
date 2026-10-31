require "razorpay"
module NetworkServices
  class WhatsappFirstPurchaseService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation

    #resp = NetworkServices::WhatsappFirstPurchaseService.call(Shop.last,OrderConfirmation.last.id)

    #resp = NetworkServices::WhatsappFirstPurchaseService.call(@shop,'919130751989')

    def initialize(shop, order_confirmation_id)
      @shop = shop
      @order_confirmation = OrderConfirmation.find(order_confirmation_id)
      
    end

    def call
      if @shop.setting.locked 
        return
      end
      # if !@shop.setting.whatsapp_operator_config.blank?
      #   branded_templates = BrandedWhatsappTemplate.where(shop_id:@shop.id,template_type:'First_Time_Purchase')
      #   if branded_templates.size>0
      #     return  NetworkServices::BrandedWhatsappService.call(@shop, @order_confirmation ,nil,branded_templates.first,'')
      #   else
      #     SlackNotifier::CLIENT.ping(
      #         text: "Error sending Branded whatsapp template for First_Time_Purchase - Template not configured - #{@shop.shopify_domain}",
      #       )
      #     return "Template not found for First_Time_Purchase for Branded whatsapp config"
      #   end
      # end

      # Test sends (sentinel order id) always go through, regardless of approval —
      # the approval status only gates live customer delivery.
      is_test_order = @order_confirmation.order_id == '1234567890'
      if !is_test_order && (@shop.setting.whatsapp_approval_status=='rejected' || (!Rails.env.development? && @shop.id > 38500 && @shop.setting.whatsapp_approval_status !='approved'))
        return
      end
      
      if @order_confirmation.blank?
        return
      end
      discount = @shop.setting.first_purchase_discount_off || "10 Percent"
      discount_code = @shop.setting.first_purchase_discount_code || "Test 10" 

      store_url= @shop.primary_domain || @shop.shopify_domain
      cutly_url = NetworkServices::CutlyLinkService.call(store_url)

      template = @shop.setting.whatsapp_first_purchase_template.presence || 'first_purchase'

        headers = {
          'Content-Type' => 'application/json',
          'authkey' => shop.setting.whatsapp_operator_config.presence || ENV.fetch("MSG91_AUTHKEY", nil),
        }
        integrated_whatsapp_number = @shop.setting.branded_whatsapp_number 
        if integrated_whatsapp_number.blank?
          integrated_whatsapp_number = ENV.fetch("WHATSAPP_NUMBER_DEFAULT", nil)
        end
        
        body = {
          "integrated_number": integrated_whatsapp_number,
          "content_type": "template",
          "payload": {
            "to": @order_confirmation.customer_number,
            "type": "template",
            "template": {
              "name": template,
              "language": {
                "code": ::Whatsapp::TemplateLanguage.for(@shop, template),
                "policy": "deterministic"
              },
              "components": [
                {
                  "type": "body",
                  "parameters": [
                    {
                      "type": "text",
                      "text": @order_confirmation.customer_name
                    },
                    {
                      "type": "text",
                      "text": @shop.owner_name
                    },
                    {
                      "type": "text",
                      "text": discount
                    },
                    {
                      "type": "text",
                      "text": discount_code
                    },
                  ]
                },
                {
                  "type": "button",
                  "index": "0",
                  "sub_type": "url",
                  "parameters": [
                    {
                      "type": "text",
                      "text": cutly_url.gsub('https://cutt.ly/','')
                    }
                  ]
                }
              ]
            },
            "messaging_product": "whatsapp"
          }
        }
        
        resp = HTTParty.post('https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/',
                                  body: body.to_json,
                                  headers: headers)
        resp_hash = resp.to_h
        if !resp_hash.blank?
          log = TwilioLog.create(
            sid: resp_hash.dig('data','message_uuid'),
            ver_type: 'WHATSAPP_FIRST_PURCHASE',
            country_code: @order_confirmation.country_code,
            customer_number: @order_confirmation.customer_number,
            status: (resp_hash['status']=='success') ? 'SUCCESS' : resp_hash.to_s,
            order_confirmation: @order_confirmation,
            shop: @shop
          )
          # Kept briefly so a 131049 "healthy ecosystem" refusal can be retried.
          if log.persisted? && log.status == 'SUCCESS'
            Whatsapp::Msg91SendCapture.remember(shop: @shop, source: log, provider_id: log.sid, url: 'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/', body: body)
          end
        end
        resp
      end
    end
  end