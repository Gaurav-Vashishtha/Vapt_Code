module NetworkServices
  #NetworkServices::SendSmsService.call(@order_confirmation.id, @shop.setting.retry_template, '',true)
  class SendSmsService < ApplicationService
    MAX_TRIES = 200

    def initialize(order_confirmation_id, template = "", dlt_id = '', is_retry = false)
      @order_confirmation_id = order_confirmation_id
      @template = template
      @dlt_id = dlt_id
      @is_retry = is_retry
    end

    def get_network_provider(country_code)
      network_provider = 'MOVIDER'
          if country_code == 'PH'
            attempts = @order_confirmation.twilio_logs.where(ver_type: "SMS").size
            if attempts % 3 ==0
              network_provider = 'MOVIDER'
            elsif attempts % 3 ==1
              network_provider = 'MOVIDER'
            elsif attempts % 3 ==2
              network_provider = 'MOVIDER'
            end
          end
      return 'MOVIDER'
    end

    def call
      @order_confirmation = OrderConfirmation.find(@order_confirmation_id)
      @shop = @order_confirmation.shop
      if @shop.setting.locked 
        return
      end
      recent_sms_count = @order_confirmation.twilio_logs.where(
        "twilio_logs.created_at >= ?", 2.minutes.ago
      ).length

      msg_count = @order_confirmation.twilio_logs.count
      fallback_to_twilio = ENV['FALLBACK_TO_TWILLIO']
    
      if  ENV['BLACKLISTED_PHONE_NUMBERS'].split(',').include?@order_confirmation.customer_number
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n Blacklisted number found order ID #{@order_confirmation.order_id} shop #{@order_confirmation.shop.shopify_domain}"
        )
        return
      end

      # sliding window checks if there are less than 3 sms in last 2 minutes
      if (@order_confirmation.source_name.blank? || @order_confirmation.source_name!='shopify_draft_order' || (!@order_confirmation.shop.setting.skip_draft_order))  &&  !@order_confirmation.customer_number.blank?  && ((@shop.setting.include_countries.blank?) || (@shop.setting.include_countries.split(',').include? @order_confirmation.country_code.upcase)) && recent_sms_count < 3 && (@is_retry || (@order_confirmation.twilio_logs.where(ver_type: "SMS").size < (@shop.setting.max_retries || MAX_TRIES)))
        if !@shop.setting.provider.blank? && !@shop.setting.provider_api_key.blank?
          resp = @shop.setting.provider.constantize.call(
            @shop.setting.provider_api_key,
            @shop.setting.provider_sender_id,
            {
              to: @order_confirmation.customer_number,
              body: get_sms_body,
              dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
            }
          )
        else
          country_code = @order_confirmation.country_code.upcase
          network_provider = get_network_provider(country_code)
          if (ENV['SMS_COUNTRY_COUNTRIES'].include?country_code) 
            sender_id = 'BNexTECH'
            api_key = ENV['SMS_COUNTRY_BASE_64_KEY']
            # base 64 encoding for API key and token Rwid37f5wtuDfBAkbYzx:cnNsv1GYPDCdIouKj8E5Yohh6TIp6SposonpTOZ3
            params = {
              text: get_sms_body,
              number:  @order_confirmation.customer_number
            }
            resp = SmsServices::SmsCountrySmsService.new(api_key, sender_id, params).call
          elsif (ENV['MSG_91_SPECIAL_COUNTRIES'].include?country_code) && ((country_code=='PH' && network_provider=='MSG_91') || country_code!='PH')
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
            flow_id = ''
            if (!@shop.setting.dlt_template_id.blank?)
              flow_id = @shop.setting.dlt_template_id
            else
              flow_id = country_code=='IN'? ENV['MSG91_FLOW_ID']:ENV['MSG91_SPECIAL_FLOW_ID']
            end
            
            customer_name = 'Customer'
            if !@order_confirmation.customer_name.blank?
              customer_name = @order_confirmation.customer_name
            end
            
            redirect = ShopifyServices::CreateRedirectService.call(@order_confirmation.shop,"https://#{ENV["APP_HOST"]}/order/verify?order_id=#{@order_confirmation.order_id}&code=#{@order_confirmation.persisted_otp}&id=#{@order_confirmation.shop.id}")
            if @is_retry
              
              link_flow_id = @shop.setting.retry_flow_id
              if link_flow_id.blank?
                link_flow_id= country_code=='IN'? ENV['MSG91_LINK_FLOW_ID']:ENV['MSG91_SPECIAL_LINK_FLOW_ID']
              end  

              resp = SmsServices::Msg91SmsRetryService.call(
                { auth_key: auth_key },
                {
                  flow_id: link_flow_id,
                  sender: sender_id ,
                  to: @order_confirmation.customer_number,
                  otp: @order_confirmation.persisted_otp,
                  store: @order_confirmation.shop.owner_name,
                  link: redirect,
                  name: customer_name,
                  number: @order_confirmation.final_order_number
                }
              )
            else
              resp = SmsServices::Msg91SmsService.call(
                { auth_key: auth_key },
                {
                  flow_id: flow_id,
                  sender: sender_id,
                  to: @order_confirmation.customer_number,
                  otp: @order_confirmation.persisted_otp,
                  store: @order_confirmation.shop.owner_name,
                  link: redirect,
                  name: customer_name
                }
              )
            end
          elsif (ENV['WAVECELL_COUNTRIES'].include?country_code) 
            resp = SmsServices::WavecellSmsService.call(
              ENV['WAVECELL_API_KEY'],
              ENV['WAVECELL_SENDER_ID'],
            {
              to: @order_confirmation.customer_number,
              body: get_sms_body,
              dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
            }
            )
          elsif (ENV['MOBEEP_COUNTRIES'].include?country_code) 
            resp = SmsServices::MobeepSmsService.call(
            ENV['MOBEEP_API_KEY'],
            ENV['MOBEEP_SENDER_ID'],
          {
            to: @order_confirmation.customer_number,
            body: get_sms_body
          }
          )
          elsif (ENV['MISR_COUNTRIES'].include?country_code)
          resp = SmsServices::MisrSmsService.call(
            ENV['MISR_API_KEY'],
            ENV['MISR_SENDER_ID'],
          {
            to: @order_confirmation.customer_number,
            body: get_sms_body
          })
          elsif (ENV['MOVIDER_COUNTRIES'].include?country_code) && ((country_code=='PH' && network_provider=='MOVIDER') || country_code!='PH')
            resp = SmsServices::MoviderSmsService.call(
              "#{ENV['MOVIDER_API_KEY']}:#{ENV['MOVIDER_API_SECRET']}",
              ENV['MOVIDER_SENDER_ID_OTP'],
            {
              to: @order_confirmation.customer_number,
              body: get_sms_body,
              dlt_id: ''
            }
            )
          elsif (ENV['VEEVOTECH_COUNTRIES'].include?country_code) 
              resp = SmsServices::VeevotechSmsService.call(
              ENV['VEEVOTECH_API_KEY'],
              ENV['VEEVOTECH_SENDER_ID'],
            {
              to: @order_confirmation.customer_number,
              body: get_sms_body
            }
            ) 
          else
            resp = TwilioServices::SendOtpService.new({
              from: ENV["TWILIO_PHONE_NUMBER"],
              to: @order_confirmation.customer_number,
              body: get_sms_body,
              country_code: @order_confirmation.country_code,
            }).call

            puts "twilio resp = #{resp}"
          end
        end
        TwilioLog.create(
          sid: resp.sid,
          ver_type: "SMS",
          country_code: @order_confirmation.country_code,
          customer_number: @order_confirmation.customer_number,
          status: resp.sid ? "SUCCESS" : resp.error,
          order_confirmation: @order_confirmation,
          num_segment: resp.num_segments,
          shop: @shop,
        )
      else
        if @order_confirmation.twilio_logs.size >= (@shop.setting.max_retries || MAX_TRIES)
          @order_confirmation.update(is_max_tried:true)
          error = "*Error* Number: #{@order_confirmation.customer_number} \n Max tries: #{@order_confirmation.twilio_logs.size} \n order_id: #{@order_confirmation.order_id} shop: #{@order_confirmation.shop.shopify_domain}"
          # SlackNotifyJob.perform_async(
          #   ":rage:  (#{Rails.env})\n  #{error}"
          # )
        error
        end
        if @order_confirmation.customer_number.blank?
          SlackNotifyJob.perform_async(
            ":rage:  (#{Rails.env})\n Customer number blank for order ID #{@order_confirmation.order_id} shop #{@order_confirmation.shop.shopify_domain}"
          )
        end
        
      end
    end

    private

    def get_shopify_order(order_confirmation)
      order_confirmation.shop.init_session
      shopify_order = ShopifyAPI::Order.find(order_confirmation.order_id)
    end

    def fetch_and_save_order_status_url(order_confirmation,shopify_order)
      if !shopify_order.blank?
        order_confirmation.update(order_status_url:shopify_order.order_status_url)
      end
      return order_confirmation
    end


    def get_sms_body
      body = @template
      if body.blank?
        body = if @order_confirmation.prepaid_link.present?
            @order_confirmation.shop.setting.prepaid_template
          else
            @order_confirmation.shop.setting.template
          end
      end

      if (body.include? "{{link}}") && !@order_confirmation.prepaid_link.blank?
        redirect = ShopifyServices::CreateRedirectService.call(@order_confirmation.shop,@order_confirmation.prepaid_link)
        if !redirect.blank?
          body = body.gsub("{{link}}", redirect)
        end
      elsif body.include? "{{link}}"

       shopify_order = get_shopify_order(@order_confirmation)
       fetch_and_save_order_status_url(@order_confirmation,shopify_order)
        redirect = ShopifyServices::CreateRedirectService.call(@order_confirmation.shop,"https://#{ENV["APP_HOST"]}/order/verify?order_id=#{@order_confirmation.order_id}&code=#{@order_confirmation.persisted_otp}&id=#{@order_confirmation.shop.id}")
        if !redirect.blank?
          body = body.gsub("{{link}}", redirect)
        end
      end
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
          .gsub("{{store_url}}", @order_confirmation.shop.shopify_domain)
          .gsub("{{number}}", order_number)
    end
  end
end
