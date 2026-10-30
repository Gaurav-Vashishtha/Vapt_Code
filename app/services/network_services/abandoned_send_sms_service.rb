module NetworkServices
  class AbandonedSendSmsService < ApplicationService
    
    def initialize(abandoned_cart_id, template = "", dlt_id = '', is_retry = false)
      @abandoned_cart_id = abandoned_cart_id
      @template = template
      @dlt_id = dlt_id
      @is_retry = is_retry
    end

    def call
      @abandoned_cart = AbandonedCart.find(@abandoned_cart_id)
      @shop = @abandoned_cart.shop
      fallback_to_twilio = ENV['FALLBACK_TO_TWILLIO']
      country_code = @abandoned_cart.country_code.upcase

      if (!@abandoned_cart.blank? && @abandoned_cart.status!='SUCCESS')
        if !@shop.setting.provider.blank? && !@shop.setting.provider_api_key.blank?
          resp = @shop.setting.provider.constantize.call(
            @shop.setting.provider_api_key,
            @shop.setting.provider_sender_id,
            {
              to: @abandoned_cart.phone,
              body: get_sms_body,
              dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
            }
          )
        elsif (ENV['WAVECELL_COUNTRIES'].include?country_code) 
          resp = SmsServices::WavecellSmsService.call(
            ENV['WAVECELL_API_KEY'],
            ENV['WAVECELL_SENDER_ID'],
          {
            to: @abandoned_cart.phone,
            body: get_sms_body,
            dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
          }
          )
        elsif (ENV['SMS_COUNTRY_COUNTRIES'].include?country_code)  #Always keep above Msg91
          sender_id = 'BNexTECH'
          api_key = ENV['SMS_COUNTRY_BASE_64_KEY']
          # base 64 encoding for API key and token Rwid37f5wtuDfBAkbYzx:cnNsv1GYPDCdIouKj8E5Yohh6TIp6SposonpTOZ3
          params = {
            text: get_sms_body,
            number:  @abandoned_cart.phone
          }
          resp = SmsServices::SmsCountrySmsService.new(api_key, sender_id, params).call
        elsif (ENV['MOVIDER_COUNTRIES'].include?country_code) 
          resp = SmsServices::MoviderSmsService.call(
            "#{ENV['MOVIDER_API_KEY']}:#{ENV['MOVIDER_API_SECRET']}",
            ENV['MOVIDER_SENDER_ID'],
          {
            to: @abandoned_cart.phone,
            body: get_sms_body,
            dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
          }
          )
        elsif (ENV['MOBEEP_COUNTRIES'].include?country_code) 
          resp = SmsServices::MobeepSmsService.call(
          ENV['MOBEEP_API_KEY'],
          ENV['MOBEEP_SENDER_ID'],
        {
          to: @abandoned_cart.phone,
          body: get_sms_body,
        }
        ) 
        elsif (ENV['MISR_COUNTRIES'].include?country_code)
        resp = SmsServices::MisrSmsService.call(
          ENV['MISR_API_KEY'],
          ENV['MISR_SENDER_ID'],
        {
          to: @abandoned_cart.phone,
          body: get_sms_body,
        })         
        elsif (ENV['VEEVOTECH_COUNTRIES'].include?country_code) 
          resp = SmsServices::VeevotechSmsService.call(
          ENV['VEEVOTECH_API_KEY'],
          ENV['VEEVOTECH_SENDER_ID'],
        {
          to: @abandoned_cart.phone,
          body: get_sms_body,
        }
        )
        elsif (ENV['MSG_91_SPECIAL_COUNTRIES'].include?country_code) && @shop.shopify_domain!='home-in-style-loutraki.myshopify.com'
            resp = ''
            sender_id = @shop.setting.sender
            if sender_id.blank?
              case 
              when ENV['WALKER_COUNTRIES'].present? && ENV['WALKER_COUNTRIES'].split(',').include?(country_code)
                sender_id = 'WALKER'
              when country_code == 'AE'
                sender_id = ENV['MSG_91_UAE_SENDER']
              when country_code == 'SA' || country_code == 'PH'
                sender_id = ENV['MSG91_SA_SENDER_ID']
              when country_code == 'IN' 
                sender_id = ENV['MSG_91_IN_SENDER']
              else
                sender_id = ENV['MSG91_SENDER_ID']
              end
            end
            
            auth_key = ENV['MSG91_AUTHKEY']

            flow_id = @shop.setting.ac_flow_id
            if flow_id.blank?
              flow_id = country_code=='IN'? ENV['MSG91_ABANDONED_TEMPLATE_ID'] : ENV['MSG91_ABANDONED_NON_IN_TEMPLATE_ID']
            end  
            url = @abandoned_cart.url
            resp = SmsServices::Msg91SmsAbandonedService.call(
              { auth_key: auth_key },
              {
                flow_id: flow_id,
                sender: sender_id,
                to: @abandoned_cart.phone,
                store: @shop.owner_name,
                url: url,
                name: @abandoned_cart.name,
              }
            )
          else
            resp = TwilioServices::SendOtpService.new({
              from: ENV["TWILIO_PHONE_NUMBER"],
              to: @abandoned_cart.phone,
              body: get_sms_body,
              country_code: country_code,
            }).call

            puts "twilio resp = #{resp}"
          end
        end
        @abandoned_cart.update(
          sid: resp.sid,
          status: resp.sid.blank? ? resp.error : "SUCCESS" ,   
        )
    end

    private

    def get_sms_body
      body = @template
      
      if (body.include? "{{a_url}}")
        redirect = ShopifyServices::CreateRedirectService.call(@abandoned_cart.shop,@abandoned_cart.url)
        if !redirect.blank?
          body = body.gsub("{{a_url}}", redirect)
        end
      end
      # body.gsub("{{otp}}", @order_confirmation.persisted_otp)
      #     .gsub("{{name}}", customer_name)
      #     .gsub("{{amount}}", @order_confirmation.order_amount)
      #     .gsub("{{store_url}}", @order_confirmation.shop.shopify_domain)
      #     .gsub("{{store_url}}", @order_confirmation.shop.shopify_domain)
      #     .gsub("{{number}}", order_number)
    end
  end
end
