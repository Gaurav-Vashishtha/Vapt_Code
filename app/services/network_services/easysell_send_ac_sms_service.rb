module NetworkServices
  class EasysellSendAcSmsService < ApplicationService


    #NetworkServices::EasysellSendAcSmsService.call(OrderConfirmation.last.id,'TestStore','example.com','+919130751989','IN')

    def initialize(order_confirmation_id,store,url, phone,country_code)
      @order_confirmation_id = order_confirmation_id
      @store = store
      @url = url
      @phone = phone
      @country_code = country_code
    end

    def call
      @order_confirmation = OrderConfirmation.find(@order_confirmation_id)
      @shop = @order_confirmation.shop
      resp = ''
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
            flow_id = country_code=='IN'? ENV.fetch("MSG91_EASYSELL_ABANDONED_IN_FLOW_ID", nil):ENV.fetch("MSG91_EASYSELL_ABANDONED_SPECIAL_FLOW_ID", nil)
            
            # if(!@order_url.blank?)
            #   @order_url = NetworkServices::CutlyLinkService.call(@order_url)
            # end

            resp = SmsServices::Msg91SmsAbandonedService.call(
              { auth_key: auth_key },
              {
                flow_id: flow_id,
                sender: sender_id,
                to: @phone,
                store: @store,
                url: @url 
              }
            )
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
          # elsif (ENV['WAVECELL_COUNTRIES'].include?country_code) 
          #   resp = SmsServices::WavecellSmsService.call(
          #     ENV['WAVECELL_API_KEY'],
          #     ENV['WAVECELL_SENDER_ID'],
          #   {
          #     to: @order_confirmation.customer_number,
          #     body: get_sms_body,
          #     dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
          #   }
          #   )
          # else
          #   resp = TwilioServices::SendOtpService.call({
          #     from: ENV["TWILIO_PHONE_NUMBER"],
          #     to: @phone,
          #     body: get_sms_body,
          #   })
          #   puts "twilio resp = #{resp}"
          end
        end
        TwilioLog.create(
          sid: resp.sid,
          ver_type: "AC_SMS",
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
      redirect = NetworkServices::CutlyLinkService.call(@url)
      body = "We notice you left these items in your cart at #{@store}.Complete your checkout now. Check it here #{redirect}"
      return body
    end
  end
end
