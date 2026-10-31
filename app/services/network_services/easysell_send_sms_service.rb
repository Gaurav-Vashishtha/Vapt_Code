module NetworkServices
  class EasysellSendSmsService < ApplicationService


    #NetworkServices::EasysellSendSmsService.call(OrderConfirmation.last.id, Shop.last.setting.retry_template, '',false,'+919130751989','TestStore','IN','1234')

    def initialize(order_confirmation_id, template = "", dlt_id = '', is_retry = false, phone='', store='',country_code='', otp='')
      @order_confirmation_id = order_confirmation_id
      @template = template
      @dlt_id = dlt_id
      @is_retry = is_retry
      @phone = phone
      @country_code = country_code
      @store = store
      @otp = otp
    end

    def call
      
      @order_confirmation = OrderConfirmation.find(@order_confirmation_id)
      @shop = @order_confirmation.shop

  
      # sliding window checks if there are less than 3 sms in last 2 minutes
      if !@phone.blank? 
        if !@shop.setting.provider.blank? && !@shop.setting.provider_api_key.blank?
          resp = @shop.setting.provider.constantize.call(
            @shop.setting.provider_api_key,
            @shop.setting.provider_sender_id,
            {
              to: @phone,
              body: get_sms_body,
              dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
            }
          )
        else
          country_code = @country_code
          if (ENV.fetch("MSG_91_SPECIAL_COUNTRIES", nil).include?country_code) 
            resp = ''
            sender_id = @shop.setting.sender
            if sender_id.blank?
              case 
              when ENV.fetch("WALKER_COUNTRIES", nil).present? && ENV.fetch("WALKER_COUNTRIES", nil).split(',').include?(country_code)
                sender_id = 'WALKER'
              when country_code == 'AE'
                sender_id = ENV.fetch("MSG_91_UAE_SENDER", nil)
              when country_code == 'SA' || country_code == 'PH'
                sender_id = ENV.fetch("MSG91_SA_SENDER_ID", nil)
              when country_code == 'IN' 
                sender_id = ENV.fetch("MSG_91_IN_SENDER", nil)
              else
                sender_id = ENV.fetch("MSG91_SENDER_ID", nil)
              end
            end
            
            auth_key = ENV.fetch("MSG91_AUTHKEY", nil)
            flow_id = ''
            if (!@shop.setting.dlt_template_id.blank?)
              flow_id = @shop.setting.dlt_template_id
            else
              flow_id = country_code=='IN'? ENV.fetch("MSG91_EASY_IN_FLOW_ID", nil):ENV.fetch("MSG91_EASYSELL_SPECIAL_FLOW_ID", nil)
            end
            
            link_flow_id= country_code=='IN'? ENV.fetch("MSG91_LINK_FLOW_ID", nil):ENV.fetch("MSG91_SPECIAL_LINK_FLOW_ID", nil)

              if @is_retry
              redirect = ShopifyServices::CreateRedirectService.call(@order_confirmation.shop,"https://#{ENV.fetch("APP_HOST", nil)}/order/verify?order_id=#{@order_confirmation.order_id}&code=#{@order_confirmation.persisted_otp}&id=#{@order_confirmation.shop.id}")
              resp = SmsServices::Msg91SmsRetryService.call(
                { auth_key: auth_key },
                {
                  flow_id: link_flow_id,
                  sender: sender_id ,
                  to: @phone,
                  otp: @otp,
                  store: @store + " -",
                  link: redirect
                }
              )
            else
              resp = SmsServices::Msg91SmsService.call(
                { auth_key: auth_key },
                {
                  flow_id: flow_id,
                  sender: sender_id,
                  to: @phone,
                  otp: @otp,
                  store: @store+" -"
                }
              )
            end
          elsif (ENV.fetch("MOVIDER_COUNTRIES", nil).include?country_code) 
            resp = SmsServices::MoviderSmsService.call(
              "#{ENV.fetch("MOVIDER_API_KEY", nil)}:#{ENV.fetch("MOVIDER_API_SECRET", nil)}",
              ENV.fetch("MOVIDER_SENDER_ID", nil),
            {
              to: @phone,
              body: get_sms_body,
              dlt_id: ''
            }
            )
          elsif (ENV.fetch("VEEVOTECH_COUNTRIES", nil).include?country_code) 
            resp = SmsServices::VeevotechSmsService.call(
            ENV.fetch("VEEVOTECH_API_KEY", nil),
            ENV.fetch("VEEVOTECH_SENDER_ID", nil),
          {
            to: @phone,
            body: get_sms_body
          }
          )
          elsif (ENV.fetch("WAVECELL_COUNTRIES", nil).include?country_code) 
            resp = SmsServices::WavecellSmsService.call(
              ENV.fetch("WAVECELL_API_KEY", nil),
              ENV.fetch("WAVECELL_SENDER_ID", nil),
            {
              to: @order_confirmation.customer_number,
              body: get_sms_body,
              dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
            }
            )
          else
            resp = TwilioServices::SendOtpService.call({
              from: ENV.fetch("TWILIO_PHONE_NUMBER", nil),
              to: @phone,
              body: get_sms_body,
            })
            puts "twilio resp = #{resp}"
          end
        end
        TwilioLog.create(
          sid: resp.sid,
          ver_type: "SMS",
          country_code: @country_code,
          customer_number: @phone,
          status: resp.sid ? "SUCCESS" : resp.error,
          order_confirmation: @order_confirmation,
          num_segment: resp.num_segments,
          shop: @shop,
        )
      else
          error = "*Error* EasySell Number: #{@customer_number} #{@store}"
          # SlackNotifyJob.perform_async(
          #   ":rage:  (#{Rails.env})\n  #{error}"
          # )
        error
      end
      if @phone.blank?
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n EasySell Number: #{@customer_number} #{@store}"
        )
      end
    end


    private

    def get_sms_body
      body = "#{@otp} is your verification code to confirm order placed on #{@store}."
      return body
    end
  end
end
