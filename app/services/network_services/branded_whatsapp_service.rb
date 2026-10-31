require "razorpay"
module NetworkServices
  class BrandedWhatsappService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation
    attr_reader :db_abandon_cart
    attr_reader :branded_whatsapp_template
    attr_reader :tracking_url

    #resp = NetworkServices::BrandedWhatsappService.call(Shop.first,OrderConfirmation.last,nil,BrandedWhatsappTemplate.last,'')

    def initialize(shop, order_confirmation,db_abandon_cart,branded_whatsapp_template,tracking_url)
      @shop = shop
      @order_confirmation = order_confirmation
      @db_abandon_cart = db_abandon_cart
      @branded_whatsapp_template = branded_whatsapp_template
      @tracking_url = tracking_url
    end

    def call
      blacklisted_numbers = ENV.fetch("BLACKLISTED_PHONE_NUMBERS", nil).split(',')
      customer_number = (@order_confirmation && @order_confirmation.customer_number) || (@db_abandon_cart && @db_abandon_cart.phone)
      
  
      if blacklisted_numbers.include?(customer_number)
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n Blacklisted number found - Whatsapp - order ID #{@order_confirmation.id}"
        )
        return
      end

      if @shop.setting.whatsapp_operator_config.blank? || @shop.setting.branded_whatsapp_number.blank?
          return
      end
      
      auth_key = @shop.setting.whatsapp_operator_config.split(":")[1]
      integrated_whatsapp_number = @shop.setting.branded_whatsapp_number
      components = build_components(@branded_whatsapp_template,@order_confirmation,@db_abandon_cart,@tracking_url)

      if @order_confirmation || @db_abandon_cart
        headers = {
          'Content-Type' => 'application/json',
          'authkey' => auth_key,
        }
        
        body = {
          "integrated_number": integrated_whatsapp_number,
          "content_type": "template",
          "payload": {
            "to": customer_number,
            "type": "template",
            "template": {
              "name": @branded_whatsapp_template.template_name,
              "language": {
                "code": @branded_whatsapp_template.language || "en",
                "policy":  "deterministic"
              },
              "components": components
            },
            "messaging_product": "whatsapp"
          }
        }
    
        response = HTTParty.post(
          'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/',
          body: body.to_json,
          headers: headers
        )
        
        resp_hash = response.to_h
        
        if !resp_hash.blank? && @order_confirmation
          TwilioLog.create(
            sid: resp_hash.dig('data','message_uuid'),
            ver_type: 'WHATSAPP',
            country_code: @order_confirmation.country_code,
            customer_number: @order_confirmation.customer_number,
            status: (resp_hash['status'] == 'success') ? 'SUCCESS' : resp_hash.to_s,
            order_confirmation: @order_confirmation,
            shop: @shop
          )
        elsif !resp_hash.blank? && @db_abandon_cart
            @db_abandon_cart.update(
            sid: resp_hash.dig('data','message_uuid'),
            status: (resp_hash['status']=='success') ? 'SUCCESS' : resp_hash.to_s,
          )
        end
        response
      end
    end

    # build_components("orderID:orderNum")
    
    def build_components(branded_whatsapp_template,order_confirmation,db_abandon_cart,tracking_url)
      parameters = []
      variables = @branded_whatsapp_template.variables
      variables.split(":").each_with_index do |value, index|
        case value
        when "order_id" 
          parameters << { "type": "text", "text":  order_confirmation.order_id} 

        when "order_number" 
          parameters << { "type": "text", "text":  order_confirmation.customer_facing_order_number} 

        when "customer_name" 
          parameters << { "type": "text", "text":  order_confirmation.customer_name} 

        when "otp" 
          parameters << { "type": "text", "text":  order_confirmation.persisted_otp} 

        when "store" 
          parameters << { "type": "text", "text":  @shop.owner_name} 

        when "order_amount" 
          parameters << { "type": "text", "text":  order_confirmation.order_amount} 

        when "prepaid_discount" 
          discount = @order_confirmation.shop.setting.prepaid_discount
          if order_confirmation.shop.setting.prepaid_discount_type=='PERCENTAGE'
            discount = discount.to_s + "%" 
          else
            discount = discount.to_s + "₹" 
          end
          parameters << { "type": "text", "text":  discount} 
          
        when "prepaid_amount_after_discount" 
          order_amount = ((ShopifyServices::PrepaidOrderService.new(nil,order_confirmation.shop, order_confirmation.id).get_total_amount)).to_i
          parameters << { "type": "text", "text":  order_amount.to_s + "₹"} 

        when "first_purchase_discount_value"
          parameters << { "type": "text", "text":  @shop.setting.first_purchase_discount_off} 

        when "first_purchase_discount_code" 
          parameters << { "type": "text", "text":  @shop.setting.first_purchase_discount_code} 

        when "abandoned_cart_discount_code" 
          parameters << { "type": "text", "text":  @shop.setting.ac_whatsapp_discount_code} 

        when "abandoned_cart_discount_value"
          parameters << { "type": "text", "text":  @shop.setting.ac_whatsapp_discount} 

        when "abandoned_cart_product_info" 
          ac_schedule = AbandonCartSchedule.find_by(cart_id: db_abandon_cart.checkout_id)
          product_info = 'Product'
          if !ac_schedule.blank?
            product_info = ac_schedule.product_info
          end
          parameters << { "type": "text", "text":  product_info} 

        else
          # Do nothing
        end
      end
      
      button_url = ""
      case branded_whatsapp_template.template_type
        when 'Order_Confirmation'
          button_url = order_confirmation.order_status_url
        when 'Order_Fulfilment'
          button_url = tracking_url
        when 'Abandoned_Checkout'
          button_url = db_abandon_cart.url
        when 'COD_Prepaid'
          button_url = "https://#{ENV.fetch("APP_HOST", nil)}/order_confirmations/redirect_payment_link?domain=#{@shop.shopify_domain}&id=#{@order_confirmation.id}"
        when 'First_Time_Purchase'
          button_url = @shop.primary_domain || @shop.shopify_domain
      end
      
      components = [{type:"body",parameters:parameters}]

      if !button_url.blank?
          button_url = NetworkServices::CutlyLinkService.call(button_url)
          button_component =    {
                "type": "button",
                "index": "0",
                "sub_type": "url",
                "parameters": [
                  {
                    "type": "text",
                    "text": button_url.gsub('https://cutt.ly/','')
                  }
                ]
              }        
          components.push(button_component)
        end
      JSON.generate(components)
    end
    
  end
end