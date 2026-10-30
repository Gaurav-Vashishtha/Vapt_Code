require "razorpay"
module NetworkServices
  class WhatsappPrepaidService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation

    #resp = NetworkServices::WhatsappPrepaidService.call(Shop.last,OrderConfirmation.last)

    #resp = NetworkServices::WhatsappPrepaidService.call(@shop,@order_confirmation)

    # `reminder` is a resolved hash from Setting#resolve_prepaid_reminder when
    # the send was scheduled from a configured prepaid reminder. nil for the
    # legacy single-template path.
    def initialize(shop, order_confirmation, reminder: nil)
      @shop = shop
      @order_confirmation = order_confirmation
      @reminder = reminder
    end

    def call
      if @shop.setting.locked 
        return
      end
      # if !@shop.setting.whatsapp_operator_config.blank?
      #   branded_templates = BrandedWhatsappTemplate.where(shop_id:@shop.id,template_type:'COD_Prepaid')
      #   if branded_templates.size>0
      #     return  NetworkServices::BrandedWhatsappService.call(@shop, @order_confirmation ,nil,branded_templates.first,'')
      #   else
      #     SlackNotifier::CLIENT.ping(
      #         text: "Error sending Branded whatsapp template for COD_Prepaid - Template not configured - #{@shop.shopify_domain}",
      #       )
      #     return "Template not found forCOD_Prepaid for Branded whatsapp config"
      #   end
      # end

      if @shop.shopify_domain=='bonsai-eg.myshopify.com'
        return  NetworkServices::GupshupWhatsappPrepaidService.call(@shop, @order_confirmation)
      end

      if !@order_confirmation.blank? && @order_confirmation.country_code=='IN'
        # Per-reminder overrides win when present, else fall through to the
        # shop-level prepaid_discount / prepaid_discount_type values.
        add_shipping   = !!(@reminder && @reminder['add_shipping'])
        discount_value = (@reminder && @reminder['discount']) || @order_confirmation.shop.setting.prepaid_discount
        discount_type  = (@reminder && @reminder['discount_type']) || @order_confirmation.shop.setting.prepaid_discount_type
        if add_shipping
          # The discount now includes the order's shipping, so show the combined
          # rupee amount — a percentage + shipping can't be shown as "%".
          resolved_discount = ShopifyServices::PrepaidOrderService.new(nil, @order_confirmation.shop, @order_confirmation.id)
                                .get_discount_amount(discount: (@reminder && @reminder['discount']), discount_type: (@reminder && @reminder['discount_type']), add_shipping: true)
          discount = "#{resolved_discount.round}₹"
        else
          discount = discount_type == 'PERCENTAGE' ? "#{discount_value}%" : "#{discount_value}₹"
        end
        
        # order_amount = ((@order_confirmation.order_amount.to_f - @shop.setting.prepaid_discount)) 
        # if @shop.setting.prepaid_discount_type=='PERCENTAGE'
        #   order_amount = ((@order_confirmation.order_amount.to_f - (@shop.setting.prepaid_discount * 0.01 * @order_confirmation.order_amount.to_f)))
        # end

        override_discount      = @reminder && @reminder['discount']
        override_discount_type = @reminder && @reminder['discount_type']
        order_amount = ShopifyServices::PrepaidOrderService.new(nil, @order_confirmation.shop, @order_confirmation.id)
                         .get_total_amount(discount: override_discount, discount_type: override_discount_type, add_shipping: add_shipping).to_i

        payment_link = "https://#{ENV['APP_HOST']}/order_confirmations/redirect_payment_link?domain=#{@shop.shopify_domain}&id=#{@order_confirmation.id}"
        payment_link = NetworkServices::CutlyLinkService.call(payment_link) 
        
        payment_link= payment_link.gsub('https://rzp.io/','').gsub('https://cutt.ly/','')
        headers = {
          'Content-Type' => 'application/json',
          'authkey' => shop.setting.whatsapp_operator_config.presence || ENV['MSG91_AUTHKEY'],
        }
        integrated_whatsapp_number = @shop.setting.branded_whatsapp_number 
        if integrated_whatsapp_number.blank?
          integrated_whatsapp_number = ENV['WHATSAPP_NUMBER_DEFAULT']
        end

        order_number = @order_confirmation.final_order_number
        # Reminder's template_key → MSG91 template name via the curated library.
        # Falls through to the shop-level default when no reminder is supplied
        # or the key isn't in the library.
        reminder_template_name =
          if @reminder && @reminder['template_key']
            ::Whatsapp::PrepaidTemplateLibrary.msg91_name_for(@reminder['template_key'])
          end
        template_name = reminder_template_name.presence ||
                        @shop.setting.whatsapp_prepaid_template_name.presence ||
                        'order_tracking_new'
        template_language = ::Whatsapp::TemplateLanguage.for(
          @shop, template_name, requested: (@reminder && @reminder['language']).presence
        )
        body = {
          "integrated_number": integrated_whatsapp_number,
          "content_type": "template",
          "payload": {
            "to": @order_confirmation.customer_number,
            "type": "template",
            "template": {
              "name": template_name,
              "language": {
                "code": template_language,
                "policy": "deterministic"
              },
              "components": [
                {
                  "type": "body",
                  "parameters": [
                    {
                      "type": "text",
                      "text": @shop.owner_name
                    },
                    {
                      "type": "text",
                      "text": order_number
                    },
                    {
                      "type": "text",
                      "text": @order_confirmation.order_amount + "₹"
                    },
                    {
                      "type": "text",
                      "text": order_amount.to_s + "₹"
                    }
                  ]
                },
                {
                  "type": "button",
                  "index": "0",
                  "sub_type": "url",
                  "parameters": [
                    {
                      "type": "text",
                      "text": payment_link
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
            ver_type: 'WHATSAPP_COD_PREPAID',
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
end