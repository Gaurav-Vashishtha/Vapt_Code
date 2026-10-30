require "razorpay"
module NetworkServices
  class WhatsappFulfilmentWithTrackingNumberService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation

    #resp = NetworkServices::WhatsappFulfilmentWithTrackingNumberService.call(Shop.last,OrderConfirmation.last,'https://google.com', 'tracking_number')

    def initialize(shop, order_confirmation, tracking_url,tracking_number)
      @shop = shop
      @order_confirmation = order_confirmation
      @tracking_url = tracking_url
      @tracking_number=tracking_number
    end


    def get_shopify_order(order_confirmation)
      shop = order_confirmation.shop
      shop.init_session
      attempts = 0
      begin
        ShopifyAPI::Order.find(order_confirmation.order_id)
      rescue ActiveResource::TooManyRequests => e
        attempts += 1
        if attempts <= 3
          sleep(10)
          retry
        end
        raise
      rescue ActiveResource::UnauthorizedAccess => e
        # Token looked fresh in our DB (expires_at in the future) but Shopify
        # rejected it anyway — revoked out of band (reinstall, scope change,
        # or an old API secret revoked before this shop's token refreshed
        # under the new one). Clear the stale metadata so the next embedded
        # admin load re-mints it via token exchange, and alert once/shop/day
        # via the existing throttled notifier rather than spamming Slack with
        # a raw backtrace+params dump for every background job that hits it.
        ShopifyServices::OfflineTokenService.invalidate!(shop, failed_token: shop.shopify_token)
        shop.notify_token_reauth_needed_once("401 on Order.find (order_id=#{order_confirmation.order_id}) — token revoked out of band")
        nil
      end
    end

    def fetch_and_save_order_status_url(order_confirmation,shopify_order)
      if !shopify_order.blank?
        order_confirmation.update(order_status_url:shopify_order.order_status_url)
      end
      return order_confirmation
    end

    def has_partial_payment_variants(shopify_order)
      shopify_order.note_attributes.any? do |note|
        note.attributes["name"] == "partial_payment_variants"
      end
    end

    def is_new_partial_order(shopify_order)
      return false unless shopify_order.note.is_a?(String)
    
      shopify_order.note.downcase.include?("partial order created".downcase)
    end

    def get_order_amount(order_confirmation)
      currency_symbol = CurrencyHelper.symbol_for(order_confirmation.currency) || order_confirmation.currency 
      shopify_order = get_shopify_order(order_confirmation)
      order_amount = order_confirmation.order_amount
      if shopify_order.blank?
        return order_amount
      end
      if has_partial_payment_variants(shopify_order) #SAME Order
        order_amount = "Total : #{currency_symbol} #{shopify_order.current_total_price} - Balance remaining: #{currency_symbol} #{shopify_order.total_outstanding}" 
      elsif is_new_partial_order(shopify_order) #New Order
        total = shopify_order.current_total_price.to_f+shopify_order.current_total_discounts.to_f
        balance = total - (shopify_order.current_total_discounts.to_f)
        order_amount = "Total : #{currency_symbol} #{total} - Balance remaining: #{currency_symbol} #{balance}" 
      else
        order_amount= order_confirmation.order_amount
      end
      return order_amount
    end

    def call
      if @shop.setting.locked 
        return
      end
      # if !@shop.setting.whatsapp_operator_config.blank?
      #   branded_templates = BrandedWhatsappTemplate.where(shop_id:@shop.id,template_type:'Order_Fulfilment')
      #   if branded_templates.size>0
      #     return  NetworkServices::BrandedWhatsappService.call(@shop, @order_confirmation ,nil,branded_templates.first,@tracking_url)
      #   else
      #     SlackNotifier::CLIENT.ping(
      #         text: "Error sending Branded whatsapp template for Order_Fulfilment - Template not configured - #{@shop.shopify_domain}",
      #       )
      #     return "Template not found for Order_Fulfilment for Branded whatsapp config"
      #   end
      # end

      if @shop.setting.whatsapp_approval_status=='rejected' || (!Rails.env.development? && @shop.id > 38500 && @shop.setting.whatsapp_approval_status !='approved') 
        return
      end
      
      if  ENV['BLACKLISTED_PHONE_NUMBERS'].split(',').include?@order_confirmation.customer_number
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n Blacklisted number found - Whatsapp - order ID #{@order_confirmation.order_id} shop #{@order_confirmation.shop.shopify_domain}"
        )
        return
      end

      if @order_confirmation.order_status_url.blank?
        shopify_order = get_shopify_order(@order_confirmation)
        @order_confirmation = fetch_and_save_order_status_url(@order_confirmation,shopify_order)
      end
        
      url_to_shorten = @tracking_url || @order_confirmation.order_status_url
      cutly_url = NetworkServices::CutlyLinkService.call(url_to_shorten)
      if cutly_url.blank? #this could be due to invalid @tracking url format...
        cutly_url =  NetworkServices::CutlyLinkService.call(@order_confirmation.order_status_url)
      end

      name = @order_confirmation.customer_name.presence || 'Dear'
      
      order_number=@order_confirmation.final_order_number

      order_amount = get_order_amount(@order_confirmation)

      template = @shop.setting.whatsapp_fulfilment_template.presence || 'order_fulfilment_with_tracking_number'
      
      if !@order_confirmation.blank? 
        integrated_whatsapp_number = @shop.setting.branded_whatsapp_number 
        if integrated_whatsapp_number.blank?
          integrated_whatsapp_number = ENV['WHATSAPP_NUMBER_DEFAULT']
        end
        headers = {
          'Content-Type' => 'application/json',
          'authkey' => shop.setting.whatsapp_operator_config.presence || ENV['MSG91_AUTHKEY'],
        }
        
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
                      "text":name
                    },
                    {
                      "type": "text",
                      "text":  @shop.owner_name
                    },
                    {
                      "type": "text",
                      "text": order_number
                    },
                    {
                      "type": "text",
                      "text": order_amount
                    },
                    {
                      "type": "text",
                      "text": @tracking_number
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
          TwilioLog.create(
            sid: resp_hash.dig('data','message_uuid'),
            ver_type: 'WHATSAPP-FULFILMENT',
            country_code: @order_confirmation.country_code,
            customer_number: @order_confirmation.customer_number,
            status: (resp_hash['status']=='success') ? 'SUCCESS' : resp_hash.to_s,
            order_confirmation: @order_confirmation,
            shop: shop
          )
        end
        resp
      end
    end
  end
end