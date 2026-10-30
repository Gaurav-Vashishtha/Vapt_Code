module NetworkJobs
class SendPreOrderOtpJob < ApplicationJob
  def perform(shop_id, params)
    @shop = Shop.find(shop_id)
    @params = params
    
    begin
      country_code = @params['country_code']
      sid = ''
      resp = nil
      
      # WhatsApp sending
      if (!@params['mode'].blank? && @params['mode'] == 'WHATSAPP')
        # Prefer the shop's own BSP (Meta) WhatsApp number when it's set up;
        # fall back to the legacy MSG91 branded path otherwise.
        sid = NetworkServices::PreOrderOtpBspService.call(@shop, @params['phone'], @params['otp'])
        if sid.blank?
          if (ENV['WHATSAPP_COUNTRIES'].split(",").include? country_code)
            resp = NetworkServices::PreWhatsappService.call(@shop, @params['phone'], @params['otp'])
            sid = resp['request_id']
          else
            SlackNotifyJob.perform_async(
              ":rage:  (#{Rails.env})\n  *Unable to send whatsapp as country not enabled.#{@params}"
            )
          end
        end

      # Custom provider SMS sending
      elsif !@shop.setting.provider.blank? && !@shop.setting.provider_api_key.blank?
        resp = @shop.setting.provider.constantize.call(
          @shop.setting.provider_api_key,
          @shop.setting.provider_sender_id,
          {
            to: @params['phone'],
            body: get_sms_body,
            dlt_id: @params['dlt_id'].blank? ? @shop.setting.dlt_template_id : @params['dlt_id'],
            header_id: @shop.setting.sender
          }
        )
      
      # Movider SMS service
      elsif (ENV['MOVIDER_COUNTRIES'].include? country_code)
        resp = SmsServices::MoviderSmsService.call(
          "#{ENV['MOVIDER_API_KEY']}:#{ENV['MOVIDER_API_SECRET']}",
          ENV['MOVIDER_SENDER_ID'],
          {
            to: @params['phone'],
            body: get_sms_body,
            dlt_id: ''
          }
        )
      
      # SMS Country service
      elsif (ENV['SMS_COUNTRY_COUNTRIES'].include? country_code)
        sender_id = 'BNexTECH'
        api_key = ENV['SMS_COUNTRY_BASE_64_KEY']
        sms_params = {
          text: get_sms_body,
          number: @params['phone']
        }
        resp = SmsServices::SmsCountrySmsService.new(api_key, sender_id, sms_params).call
      
      # MSG91 special countries
      elsif (ENV['MSG_91_SPECIAL_COUNTRIES'].include? country_code)
        sender_id = get_msg91_sender_id(country_code)
        auth_key = @shop.setting.msg91_auth_key
        flow_id = get_msg91_flow_id(country_code)
        
        resp = SmsServices::Msg91SmsService.call(
          { auth_key: auth_key },
          {
            flow_id: flow_id,
            sender: sender_id,
            to: @params['phone'],
            otp: @params['otp'],
            store: @shop.owner_name,
            short_url: 0
          }
        )
      
      # Wavecell SMS service
      elsif (ENV['WAVECELL_COUNTRIES'].include? country_code)
        resp = SmsServices::WavecellSmsService.call(
          ENV['WAVECELL_API_KEY'],
          ENV['WAVECELL_SENDER_ID'],
          {
            to: @params['phone'],
            body: get_sms_body,
            dlt_id: ''
          }
        )
      
      # Veevotech SMS service
      elsif (ENV['VEEVOTECH_COUNTRIES'].include? country_code)
        resp = SmsServices::VeevotechSmsService.call(
          ENV['VEEVOTECH_API_KEY'],
          ENV['VEEVOTECH_SENDER_ID'],
          {
            to: @params['phone'],
            body: get_sms_body,
            header_id: @shop.setting.sender
          }
        )
      
      # Mobeep SMS service
      elsif (ENV['MOBEEP_COUNTRIES'].include? country_code)
        resp = SmsServices::MobeepSmsService.call(
          ENV['MOBEEP_API_KEY'],
          ENV['MOBEEP_SENDER_ID'],
          {
            to: @params['phone'],
            body: get_sms_body
          }
        )
      
      # Misr SMS service
      elsif (ENV['MISR_COUNTRIES'].include? country_code)
        resp = SmsServices::MisrSmsService.call(
          ENV['MISR_API_KEY'],
          ENV['MISR_SENDER_ID'],
          {
            to: @params['phone'],
            body: get_sms_body
          }
        )
      
      # Default Twilio service
      else
        phone_number = @params['phone']
        if !phone_number.strip.starts_with?('+')
          phone_number = '+' + phone_number
        end
        
        resp = TwilioServices::SendOtpService.new({
          from: ENV["TWILIO_PHONE_NUMBER"],
          to: phone_number,
          body: get_sms_body,
          country_code: @params['country_code'],
        }).call
        
        puts "twilio resp = #{resp}"
      end
      
      # Get SID from response
      sid = @params['mode'] == 'WHATSAPP' ? sid : resp&.sid
      
      # Update PreOrderOtp record with result
      update_otp_record(sid, resp)
      
      # Return result
      if sid.blank?
        detail =
          if resp.respond_to?(:twilio_detail)
            resp.twilio_detail
          end
        err =
          if resp.respond_to?(:error)
            resp.error
          end

        notes =
          if detail.to_s.strip != ""
            detail.to_s
          elsif err.to_s.strip != ""
            err.to_s
          else
            "Unable to send OTP, Please check the number"
          end
        { status: 'Error', notes: notes }
      else
        { status: 'Success', notes: 'OTP sent successfully', sid: sid }
      end
      
    rescue Exception => e
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n  *Error in PreOTP Job* #{@shop.shopify_domain}  #{@params} \n Response #{resp} #{e.backtrace}"
      )
      { status: 'Error', notes: 'Failed to send OTP', error: e.message }
    end
  end

  private

  def get_sms_body
    body = @params['template'] || @shop.setting.template
    body.gsub("{{otp}}", @params['otp'].to_s).gsub("{{store_url}}", @shop.shopify_domain)
  end

  def get_msg91_sender_id(country_code)
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
    
    sender_id
  end

  def get_msg91_flow_id(country_code)
    if !@shop.setting.dlt_template_id.blank?
      @shop.setting.dlt_template_id
    else
      country_code == 'IN' ? ENV['MSG91_FLOW_ID'] : ENV['MSG91_SPECIAL_FLOW_ID']
    end
  end

  def update_otp_record(sid, resp)
    # Find the PreOrderOtp record and update it
    otp_record = PreOrderOtp.find_by(
      device_id: @params['device_id'],
      phone: @params['phone'],
      otp: @params['otp']
    )
    
    if otp_record
      # Determine ver_type based on mode
      ver_type = (!@params['mode'].blank? && @params['mode'] == 'WHATSAPP') ? 'WHATSAPP' : 'SMS'
      
      otp_record.update(
        sid: sid,
        status: sid ? "SUCCESS" : (resp&.error || "FAILED"),
        ver_type: ver_type
      )
    end
  end
end
end