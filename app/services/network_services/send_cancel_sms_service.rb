module NetworkServices
  class SendCancelSmsService < ApplicationService
    def initialize(order_confirmation_id)
      @order_confirmation_id = order_confirmation_id
    end

    #NetworkServices::SendCancelSmsService.call(order_confirmation.id)
    #NetworkServices::SendCancelSmsService.call(OrderConfirmation.last.id)

    def call
      @order_confirmation = OrderConfirmation.find(@order_confirmation_id)
      @shop = @order_confirmation.shop
      country_code = @order_confirmation.country_code.upcase

      if !@order_confirmation.customer_number.blank? &&
          @shop.setting.cancel_notif_enabled
        if !@shop.setting.provider.blank? && !@shop.setting.provider_api_key.blank?
          resp = @shop.setting.provider.constantize.call(
            @shop.setting.provider_api_key,
            @shop.setting.provider_sender_id,
            {
              to: @order_confirmation.customer_number,
              body: get_sms_body,
              dlt_id: ''
            }
          )
        elsif (ENV.fetch("MOVIDER_COUNTRIES", nil).include?country_code) 
          resp = SmsServices::MoviderSmsService.call("#{ENV.fetch("MOVIDER_API_KEY", nil)}:#{ENV.fetch("MOVIDER_API_SECRET", nil)}",
            ENV.fetch("MOVIDER_SENDER_ID", nil),
          {
            to: @order_confirmation.customer_number,
            body: get_sms_body,
            dlt_id: ''
          }
          )
        elsif (ENV.fetch("MSG_91_SPECIAL_COUNTRIES", nil).include?country_code) 
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

            flow_id = @shop.setting.cancel_flow_id
            if flow_id.blank?
              flow_id =  ENV.fetch("MSG91_CANCEL_TEMPLATE_ID", nil)
            end 
            
            customer_name = 'Customer'
            if !@order_confirmation.customer_name.blank?
              customer_name = @order_confirmation.customer_name
            end
            
            resp = SmsServices::Msg91SmsCancelService.call(
              { auth_key: auth_key },
              {
                flow_id: flow_id,
                sender: sender_id ,
                to: @order_confirmation.customer_number,
                store: @order_confirmation.shop.primary_domain.blank? ? @order_confirmation.shop.shopify_domain : @order_confirmation.shop.primary_domain,
                name: customer_name
              }
            )
          elsif (ENV.fetch("WAVECELL_COUNTRIES", nil).include?country_code) 
            resp = SmsServices::WavecellSmsService.call(
              ENV.fetch("WAVECELL_API_KEY", nil),
              ENV.fetch("WAVECELL_SENDER_ID", nil),
            {
              to: @order_confirmation.customer_number,
              body: get_sms_body,
              dlt_id: ''
            }
            )
          elsif (ENV.fetch("VEEVOTECH_COUNTRIES", nil).include?country_code) 
            resp = SmsServices::VeevotechSmsService.call(
            ENV.fetch("VEEVOTECH_API_KEY", nil),
            ENV.fetch("VEEVOTECH_SENDER_ID", nil),
          {
            to: @order_confirmation.customer_number,
            body: get_sms_body,
          }
          )
          else
            resp = TwilioServices::SendOtpService.new({
              from: ENV.fetch("TWILIO_PHONE_NUMBER", nil),
              to: @order_confirmation.customer_number,
              body: get_sms_body,
              country_code: @order_confirmation.country_code,
            }).call
            puts "twilio resp = #{resp}"
          end
        TwilioLog.create(
          sid: resp.sid.blank? ? 'FAILED' : resp.sid+"_CANCEL",
          ver_type: "SMS",
          country_code: @order_confirmation.country_code,
          customer_number: @order_confirmation.customer_number,
          status: resp.sid ? "SUCCESS" : resp.error,
          order_confirmation: @order_confirmation,
          num_segment: resp.num_segments,
          shop: @shop,
        )
      end
    end

    private

    def get_sms_body
      body = @shop.setting.cancel_template
      customer_name=''
      if !@order_confirmation.customer_name.blank?
        customer_name = @order_confirmation.customer_name&.partition(" ")&.first
      end

      order_number=''
      if !@order_confirmation.order_number.blank?
        order_number = @order_confirmation.order_number
      end

      body.gsub("{{otp}}", @order_confirmation.persisted_otp)
          .gsub("{{name}}", customer_name)
          .gsub("{{amount}}", @order_confirmation.order_amount)
          .gsub("{{store_url}}", @order_confirmation.shop.shopify_domain)
          .gsub("{{number}}", order_number)
    end
  end
end
