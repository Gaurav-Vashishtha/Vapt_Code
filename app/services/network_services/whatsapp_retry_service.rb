require "razorpay"
module NetworkServices
  class WhatsappRetryService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation

    #resp = NetworkServices::WhatsappRetryService.call(Shop.first,OrderConfirmation.last)

    # Never raises. This read only refreshes order_status_url, which the
    # message does not even use — it must never be able to stop the send.
    def get_shopify_order(order_confirmation)
      ShopifyServices::SafeOrderReader.find(order_confirmation.shop, order_confirmation.order_id)
    end

    def fetch_and_save_order_status_url(order_confirmation,shopify_order)
      if !shopify_order.blank?
        order_confirmation.update(order_status_url:shopify_order.order_status_url)
      end
      return order_confirmation
    end

    def initialize(shop, order_confirmation)
      @shop = shop
      @order_confirmation = order_confirmation
      # Skip Shopify API calls for test orders
      is_test_order = @order_confirmation.order_id == '8888888888' || @order_confirmation.status == 'Test-Order'
      unless is_test_order
        shopify_order = get_shopify_order(@order_confirmation)
        fetch_and_save_order_status_url(@order_confirmation,shopify_order)
      end
    end

    def call
      if @shop.setting.locked 
        return
      end
      
      # Check if it's a test order
      is_test_order = @order_confirmation.order_id == '8888888888' || @order_confirmation.status == 'Test-Order'
      
      # Skip approval status check for test orders
      # unless is_test_order
      #   if @shop.setting.whatsapp_approval_status == 'rejected' || (!Rails.env.development? && @shop.id > 38500 && @shop.setting.whatsapp_approval_status != 'approved')
      #     return
      #   end
      # end
      
      confirmation_url = NetworkServices::CutlyLinkService.call("https://#{ENV.fetch("APP_HOST", nil)}/order/verify?order_id=#{@order_confirmation.order_id}&code=#{@order_confirmation.persisted_otp}&id=#{@order_confirmation.shop.id}")
      if !@order_confirmation.blank? 
        integrated_whatsapp_number = @shop.setting.branded_whatsapp_number 
        if integrated_whatsapp_number.blank?
          integrated_whatsapp_number = ENV.fetch("WHATSAPP_NUMBER_DEFAULT", nil)
        end

        if @shop.shopify_domain=='bonsai-eg.myshopify.com'
          return  NetworkServices::GupshupWhatsappRetryService.call(@shop, @order_confirmation)
        end

        customer_name = Notifications::Defaults.name(order_confirmation.customer_name)
        language_code = ::Whatsapp::TemplateLanguage.for(@shop, @shop.setting.whatsapp_cod_verification_template.presence || 'cod_verification_link5')
        if @shop.shopify_domain=='komodoofficial.myshopify.com'
          language_code = "it"
        end

        template_name = @shop.setting.whatsapp_cod_verification_template.presence || 'cod_verification_link5'

        template = {
          "name": template_name,
          "language": {
          "code": language_code,
          "policy": "deterministic"
          },
          "components": [
          {
          "type": "body",
          "parameters": [
          {
          "type": "text",
          "text": customer_name
          },
          {
          "type": "text",
          "text": Notifications::Defaults.value(@shop.owner_name)
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
          "text": Notifications::Defaults.value(confirmation_url.to_s.delete_prefix('https://cutt.ly/'))
          }
          ]
          }
          ]
          }
          payload = {
          "to": @order_confirmation.customer_number,
          "type": "template",
          "template": template,
          "messaging_product": "whatsapp"
          }
          
          request_body = {
          "integrated_number": integrated_whatsapp_number,
          "content_type": "template",
          "payload": payload
          }
          response = HTTParty.post(
          "https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/",
          headers: {
          "Content-Type": "application/json",
          "authkey": shop.setting.whatsapp_operator_config.presence || ENV.fetch("MSG91_AUTHKEY", nil)
          },
          body: request_body.to_json
          )
        resp_hash = response.to_h
        if !resp_hash.blank? 
          log = TwilioLog.create(
            sid: resp_hash.dig('data','message_uuid'),
            ver_type: 'WHATSAPP',
            country_code: @order_confirmation.country_code,
            customer_number: @order_confirmation.customer_number,
            status:  (resp_hash['status']=='success') ? 'SUCCESS' : resp_hash.to_s,
            order_confirmation: @order_confirmation,
            shop: shop
          )
          # Kept briefly so a 131049 "healthy ecosystem" refusal can be retried.
          if log.persisted? && log.status == 'SUCCESS'
            Whatsapp::Msg91SendCapture.remember(shop: shop, source: log, provider_id: log.sid, url: 'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/', body: request_body)
          end
        end
        response
      end
    end
  end
end
