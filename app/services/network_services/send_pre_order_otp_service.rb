module NetworkServices
  class SendPreOrderOtpService < ApplicationService
    MAX_TRIES = 2 #Maximum number of permissible tries, if value is greater than this then throttle.

    #params = {"country_code"=>"IN", "phone"=>"919130751989", "otp"=>"1234", "ip_address"=>"10.1.1.14", "device_id"=>"abjdsjdhs","mode"=>'whatsapp'}
    # NetworkServices::SendPreOrderOtpService.call(shop.id, params)

    def get_otp
      # pastOtps = PreOrderOtp.where(device_id: @params['device_id'], phone: @params['phone'])
      #   .where("created_at >= ?", 30.minutes.ago)
      #   .order("pre_order_otps.created_at DESC")
      
      # if !pastOtps.blank?
      #   return pastOtps.first.otp
      # end
      
      Random.rand(1111...9999)
    end

    def get_auto_country_code(phone)
      return Phonelib.parse(phone).country  
      rescue Exception => e
      nil
    end

    def checkout_widget_domain_enabled?(shopify_domain)
      return false if shopify_domain.blank?
      return false if ENV['CHECKOUT_WIDGET_DOMAINS'].blank?
      
      enabled_domains = ENV['CHECKOUT_WIDGET_DOMAINS'].split(',').map(&:strip).reject(&:blank?)
      enabled_domains.any? { |domain| shopify_domain.include?(domain) }
    end


    def clean_phone_number(phone, country_code)
      if !phone.blank?
        phone = phone.tr('^0-9', '').sub!(/^0*/, '')
      end
      Phonelib.parse(phone, country_code).to_s
    rescue Exception => e
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n *Error* Phonelib parse \n Phone: #{phone}  \n country_code: #{country_code} \n error: #{e.message}"
      )
      phone
    end

    def initialize(shop_id, params)
      @shop = Shop.find(shop_id)
      @params = params
    end

    def is_throttled(lookback_mins, allowed_tries)
      cutoff_time = lookback_mins.minutes.ago
      
      # Build OR conditions for each parameter that exists
      conditions = []
      params_values = []
      
      unless @params['ip_address'].blank?
        conditions << "ip_address = ?"
        params_values << @params['ip_address']
      end
      
      if @params['device_id'].present?
        conditions << "device_id = ?"
        params_values << @params['device_id']
      end
      
      if @params['phone'].present?
        conditions << "phone = ?"
        params_values << @params['phone']
      end
      
      return false if conditions.empty?
      
      # Single query: count records matching ANY of the conditions
      where_clause = "(#{conditions.join(' OR ')}) AND created_at >= ?"
      total_tries = PreOrderOtp.otp_sends
        .where(where_clause, *params_values, cutoff_time)
        .count
      
      if total_tries > allowed_tries
        puts "Throttling: lookback_mins=#{lookback_mins}, allowed_tries=#{allowed_tries}, total_tries=#{total_tries}, params=#{@params}"
        return true
      end
      
      false
    end

    def call
      begin
        # Check if shop is locked
        if @shop.setting.locked
          return {
            'status': 'Error',
            'Notes': 'OTP balance is exhausted. Please reach out to support@notifiktech.com or chat support of COD King for steps to resume.'
          }
        end

        if PreOrderOtpCheckoutPageGuard.checkout_page_request?(@params) &&
            !PreOrderOtpCheckoutPageGuard.allowed_for_checkout_api?(@shop)
          return {
            status: "Error",
            Notes: "Checkout extension OTP is not enabled for this billing plan. Upgrade to Enterprise or contact support.",
            code: "checkout_otp_plan_forbidden"
          }
        end

        # Check throttling
        if is_throttled(1, 3) || is_throttled(5, 10) || is_throttled(1440, 30)
          puts 'Greater than max tries, throttled'
          return {
            'status' => 'Error',
            'Notes' => 'Too many verification attempts. Please wait a few minutes and try again.',
            'code' => 'pre_order_otp_throttled'
          }
        end
        country_code = @params['country_code']
        phone_lib_country = ''
        if checkout_widget_domain_enabled?(@shop.shopify_domain)
          phone_lib_country = get_auto_country_code(@params['phone'])
        end

        # Generate OTP and clean phone number
        @params['otp'] = get_otp        
        @params['phone'] = clean_phone_number(@params['phone'], @params['country_code'])

        if !phone_lib_country.blank?
          country_code=phone_lib_country
        end

        # Validate Indian phone numbers
        if country_code == 'IN' && @params['phone'].to_s.gsub('+', '').length > 12
          return nil
        end

        # Check if phone is blocked (ignore empty segments from trailing commas / extra spaces)
        blocked_phones = @shop.setting.pre_block_phone.to_s.split(',').map(&:strip).reject(&:blank?)
        phone_for_block = @params['phone'].to_s
        is_blocked = blocked_phones.any? { |blocked| phone_for_block.include?(blocked) }

        if is_blocked
          puts 'Phone number blocked.'
          return {
            'status' => 'Error',
            'Notes' => 'This phone number cannot be used for verification.',
            'code' => 'pre_order_otp_phone_blocked'
          }
        end

        # Check if processing should be synchronous or asynchronous
        if ENV['SMS_PROCESSING_MODE'] == 'SYNC'
          # Synchronous SMS processing
          sid = ''
          resp = nil

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

          elsif !@shop.setting.provider.blank? && !@shop.setting.provider_api_key.blank?
            resp = @shop.setting.provider.constantize.call(
              @shop.setting.provider_api_key,
              @shop.setting.provider_sender_id,
              {
                to: @params['phone'],
                body: get_sms_body,
                dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id,
                header_id: @shop.setting.sender
              }
            )

          elsif (ENV['MOVIDER_COUNTRIES'].include? country_code)
            resp = SmsServices::MoviderSmsService.call(
              "#{ENV['MOVIDER_API_KEY']}:#{ENV['MOVIDER_API_SECRET']}",
              ENV['MOVIDER_SENDER_ID_OTP'],
              {
                to: @params['phone'],
                body: get_sms_body,
                dlt_id: ''
              }
            )

          elsif (ENV['SMS_COUNTRY_COUNTRIES'].include? country_code)
            sender_id = 'BNexTECH'
            api_key = ENV['SMS_COUNTRY_BASE_64_KEY']
            params = {
              text: get_sms_body,
              number: @params['phone']
            }
            resp = SmsServices::SmsCountrySmsService.new(api_key, sender_id, params).call

          elsif (ENV['MSG_91_SPECIAL_COUNTRIES'].include? country_code)
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
            
            auth_key = @shop.setting.msg91_auth_key
            flow_id = ''
            if (!@shop.setting.dlt_template_id.blank?)
              flow_id = @shop.setting.dlt_template_id
            else
              flow_id = country_code == 'IN' ? ENV['MSG91_FLOW_ID'] : ENV['MSG91_SPECIAL_FLOW_ID']
            end
            
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
              
          elsif (ENV['MOBEEP_COUNTRIES'].include? country_code)
            resp = SmsServices::MobeepSmsService.call(
              ENV['MOBEEP_API_KEY'],
              ENV['MOBEEP_SENDER_ID'],
              {
                to: @params['phone'],
                body: get_sms_body
              }
            )

          elsif (ENV['MISR_COUNTRIES'].include? country_code)
            resp = SmsServices::MisrSmsService.call(
              ENV['MISR_API_KEY'],
              ENV['MISR_SENDER_ID'],
              {
                to: @params['phone'],
                body: get_sms_body
              }
            )

          else
            if !@params['phone'].strip.starts_with?('+')
              @params['phone'] = '+' + @params['phone']
            end
            resp = TwilioServices::SendOtpService.new({
              from: ENV["TWILIO_PHONE_NUMBER"],
              to: @params['phone'],
              body: get_sms_body,
              country_code: @params['country_code'],
            }).call
    
            puts "twilio resp = #{resp}"
          end

          # Get SID from response
          sid = @params['mode'] == 'WHATSAPP' ? sid : resp&.sid
          
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
            return { 'status': 'Error', 'Notes': notes }
          end
    
          # Determine ver_type based on mode
          ver_type = (!@params['mode'].blank? && @params['mode'] == 'WHATSAPP') ? 'WHATSAPP' : 'SMS'
    
          # Create PreOrderOtp record with result
          PreOrderOtp.create(
            sid: sid,
            country_code: @params['country_code'],
            phone: @params['phone'],
            status: sid ? "SUCCESS" : resp&.error,
            ip_address: @params['ip_address'],
            device_id: @params['device_id'],
            otp: @params['otp'],
            cart_details: @params['cart_details'],
            ver_type: ver_type,
            shop: @shop
          )
          
          return { 'status': 'Success', 'Notes': 'OTP sent successfully', 'sid': sid }

        else
          # Asynchronous SMS processing
          # Determine ver_type based on mode
          ver_type = (!@params['mode'].blank? && @params['mode'] == 'WHATSAPP') ? 'WHATSAPP' : 'SMS'
          
          # Create PreOrderOtp record first
          otp_record = PreOrderOtp.create(
            sid: nil, # Will be updated by the job
            country_code: @params['country_code'],
            phone: @params['phone'],
            status: "PENDING",
            ip_address: @params['ip_address'],
            device_id: @params['device_id'],
            otp: @params['otp'],
            cart_details: @params['cart_details'],
            ver_type: ver_type,
            shop: @shop
          )

          # Queue the SMS sending job
          # Convert ActionController::Parameters to plain Hash for Sidekiq
          sanitized_params = sanitize_params_for_sidekiq(@params)
          job_params = sanitized_params.merge({
            'shop_id' => @shop.id,
            'template' => @template,
            'dlt_id' => @dlt_id
          })
          
          NetworkJobs::SendPreOrderOtpJob.perform_async(@shop.id, job_params)

          return {
            'status': 'Success',
            'Notes': 'OTP queued for sending',
            'otp_record_id': otp_record.id
          }
        end

      rescue Exception => e
        Rails.logger.error("[SendPreOrderOtpService] #{e.class}: #{e.message}\n#{e.backtrace&.first(20)&.join("\n")}")
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Error in PreOTP Service* #{@shop.shopify_domain}  #{@params} \n#{e.class}: #{e.message}\n#{e.backtrace&.first(12)&.join("\n")}"
        )
        return {
          'status': 'Error',
          'Notes': "Failed to process OTP request: #{e.class}: #{e.message}",
        }
      end
    end

    private

    def get_sms_body
      body = @template
      if body.blank?
        body = @shop.setting.template
      end
      body.gsub("{{otp}}", @params['otp'].to_s).gsub("{{store_url}}", @shop.shopify_domain)
    end

    def sanitize_params_for_sidekiq(params)
      case params
      when ActionController::Parameters
        # Convert to plain Hash and recursively sanitize values
        Hash[params.to_unsafe_h.map { |k, v| [k.to_s, sanitize_params_for_sidekiq(v)] }]
      when ActiveSupport::HashWithIndifferentAccess
        # Convert to plain Hash and recursively sanitize values
        Hash[params.to_h.map { |k, v| [k.to_s, sanitize_params_for_sidekiq(v)] }]
      when Hash
        # Convert to plain Hash and recursively sanitize values
        Hash[params.map { |k, v| [k.to_s, sanitize_params_for_sidekiq(v)] }]
      when Array
        params.map { |item| sanitize_params_for_sidekiq(item) }
      else
        params
      end
    end
  end
end