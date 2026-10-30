module NetworkJobs
  class SendFulfilmentSmsJob < ApplicationJob
    def add_fulfilment_webhook_temp 
      Shop.all.each do |shop|
        begin
        if(!shop.setting.enable_fulfilment_message.blank? && shop.setting.enable_fulfilment_message==true)
        shop.init_session
        webhook = {
        topic: 'orders/fulfilled',
        address: "https://#{ENV['APP_HOST']}/order_confirmations/order_fulfilled",
        format: 'json'
        }
        if ShopifyAPI::Webhook.new(webhook).save 
          puts "Webhook added #{shop.shopify_domain}" 
        else
          puts "Webhook failed #{shop.shopify_domain}"
        end
      end
      rescue Exception=> e
        puts "Webhook failed #{shop.shopify_domain}"
      end
  
      end
    end 

    # def update_default_template 
    #   Shop.all.each do |shop|
    #     if shop.setting.blank?
    #       next
    #     end
    #     if shop.primary_locale.blank?
    #       I18n.locale = :en 
    #     else 
    #       if I18n.available_locales.excluding(:bg, :ar, :hi, :hr, :sl).include?(shop.primary_locale[0..1]&.to_sym)
    #         I18n.locale = shop.primary_locale[0..1]&.to_sym
    #       else
    #         I18n.locale = :en
    #       end
    #     end
    #     puts I18n.locale
    #     if shop.setting.fulfilment_flow_id.blank?
    #       store = shop.owner_name
    #       if store.end_with?("-")
    #         store = store.chop
    #       end
    #       shop.setting.update(fulfilment_template: I18n.t('admin.fulfilment_template_default', {store: store}))
    #       puts "Updated shop #{shop.shopify_domain}"
    #     end
    #   end
    # end 

    def enrich_order_confirmation(params, order_confirmation)
      customer_phone = order_confirmation.customer_number || params.dig('shipping_address','phone') || params.dig('billing_address','phone') || params.dig('customer','phone')
      name = order_confirmation.customer_name ||  params.dig('shipping_address','name')
      order_number = order_confirmation.order_number || params['order_number']
      order_status_url = order_confirmation.order_status_url || params['order_status_url']
      order_amount = order_confirmation.order_amount || params['total_price']
      country_code = order_confirmation.country_code || order_confirmation.get_country_code(params)
      order_confirmation.update(customer_number: customer_phone, customer_name: name, order_number: order_number, order_amount: order_amount, country_code: country_code)
      order_confirmation
    end

    # The fulfilment webhook payload sometimes omits the recipient name/phone/
    # country (e.g. guest checkouts, partial address). Only when the record is
    # still incomplete after enrich do we pay for a fresh Shopify read and
    # backfill from the canonical order — so we don't send with "Customer" or
    # bail on a blank phone.
    def backfill_from_shopify_if_incomplete(shop, order_confirmation, params)
      return order_confirmation if params['id'].blank?
      return order_confirmation if order_confirmation.customer_name.present? &&
                                   order_confirmation.customer_number.present? &&
                                   order_confirmation.country_code.present?

      shop.init_session
      shopify_order = ShopifyAPI::Order.find(params['id'])
      return order_confirmation if shopify_order.blank?

      attrs = {}
      attrs[:customer_name]   = shopify_customer_name(shopify_order)  if order_confirmation.customer_name.blank?
      attrs[:customer_number] = shopify_customer_phone(shopify_order) if order_confirmation.customer_number.blank?
      attrs[:country_code]    = shopify_country_code(shopify_order)   if order_confirmation.country_code.blank?
      if order_confirmation.order_status_url.blank? && shopify_order.order_status_url.present?
        attrs[:order_status_url] = shopify_order.order_status_url
      end

      attrs.reject! { |_, v| v.blank? }
      order_confirmation.update(attrs) if attrs.any?
      order_confirmation
    rescue => e
      Rails.logger.warn("[send_fulfilment_sms] shopify re-read failed order=#{params['id']}: #{e.class}: #{e.message}")
      order_confirmation
    end

    def shopify_customer_name(shopify_order)
      cust = shopify_order.customer
      full = [cust&.first_name, cust&.last_name].compact.join(" ").strip
      return full if full.present?

      shopify_order.shipping_address&.name.presence || shopify_order.billing_address&.name.presence
    rescue
      nil
    end

    def shopify_customer_phone(shopify_order)
      shopify_order.shipping_address&.phone.presence ||
        shopify_order.billing_address&.phone.presence ||
        shopify_order.customer&.phone.presence ||
        shopify_order.phone.presence
    rescue
      nil
    end

    def shopify_country_code(shopify_order)
      (shopify_order.shipping_address&.country_code.presence ||
        shopify_order.billing_address&.country_code.presence ||
        shopify_order.customer&.default_address&.country_code.presence)&.upcase
    rescue
      nil
    end

    def perform(params,shop_id,mode='')
      begin
      shop = Shop.find(shop_id)
      if shop.setting.locked 
        return
      end
      order_confirmation = OrderConfirmation.find_or_initialize_by(order_id: params['id'], shop: shop)
      order_confirmation = enrich_order_confirmation(params,order_confirmation)
      order_confirmation = backfill_from_shopify_if_incomplete(shop, order_confirmation, params)
      resp = ''
      country_code = order_confirmation.country_code || params.dig('shipping_address','country_code') || params.dig('billing_address','country_code') || params.dig('customer','default_address','country_code')

      
      if country_code.blank?
        # SlackNotifyJob.perform_async(
        #   ":rage:  (#{Rails.env})\n  *Counld not find country in fulfilment #{params}"
        # )
        return
      end
      country_code=country_code.upcase
      phone = order_confirmation.customer_number || params.dig('shipping_address','phone') || params.dig('billing_address','phone') || params.dig('customer','default_address','phone')
      
      if phone.blank?
        # SlackNotifyJob.perform_async(
        #   ":rage:  (#{Rails.env})\n  *Counld not find Phone in fulfilment #{params}"
        # )
        return
      end

      order_number = order_confirmation.final_order_number
      
      tracking_number=''
      if !params['fulfillments'].blank? && (!params['fulfillments'].first['tracking_number'].blank?)
        tracking_number = params['fulfillments'].first['tracking_number']
      end

      tracking_url = get_tracking_url(params)
      if shop.setting.fulfilment_whatsapp && (order_confirmation.order_id!="9999999999")
        if tracking_number.blank?
          resp = NetworkServices::WhatsappFulfilmentService.call(shop,order_confirmation,tracking_url)
        else
          resp = NetworkServices::WhatsappFulfilmentWithTrackingNumberService.call(shop,order_confirmation,tracking_url, tracking_number)
        end
        if !shop.setting.enable_fulfilment_message
          return
        end
      end

      @sms_tracking_url = tracking_url.presence || order_confirmation.order_status_url.presence || params['order_status_url']
      if !@sms_tracking_url.blank?
        redirect = ShopifyServices::CreateRedirectService.call(shop, @sms_tracking_url)
        @sms_tracking_url = redirect if !redirect.blank?
      end

      flow_id = shop.setting.fulfilment_flow_id
      if shop.setting.fulfilment_flow_id.blank?
        if tracking_url.blank?
          flow_id = country_code=='IN'? ENV['MSG91_FULFILMENT_TEMPLATE_ID']:ENV['MSG91_FULFILMENT_NON_INDIA_TEMPLATE_ID']
        else
          flow_id = country_code=='IN'? ENV['MSG91_FULFILMENT_URL_TEMPLATE_ID']:ENV['MSG91_FULFILMENT_URL_NON_INDIA_TEMPLATE_ID']
        end      
      end
  
      if !shop.setting.provider.blank? && !shop.setting.provider_api_key.blank?
        resp = shop.setting.provider.constantize.call(
          shop.setting.provider_api_key,
          shop.setting.provider_sender_id,
          {
            to: phone,
            body: get_sms_body(order_confirmation,params,order_number),
            dlt_id: ''
          }
        )
      elsif (ENV['MOVIDER_COUNTRIES'].include?country_code) 
        resp = SmsServices::MoviderSmsService.call(
          "#{ENV['MOVIDER_API_KEY']}:#{ENV['MOVIDER_API_SECRET']}",
          ENV['MOVIDER_SENDER_ID'],
        {
          to: phone,
          body: get_sms_body(order_confirmation,params,order_number),
          dlt_id: ''
        }
        )
      elsif (ENV['SMS_COUNTRY_COUNTRIES'].include?country_code)  #Always keep above Msg91
        sender_id = 'BNexTECH'
        api_key = ENV['SMS_COUNTRY_BASE_64_KEY']
        # base 64 encoding for API key and token Rwid37f5wtuDfBAkbYzx:cnNsv1GYPDCdIouKj8E5Yohh6TIp6SposonpTOZ3
        params = {
          text: get_sms_body(order_confirmation,params,order_number),
          number:  phone,
        }
        resp = SmsServices::SmsCountrySmsService.new(api_key, sender_id, params).call
      elsif (ENV['MSG_91_SPECIAL_COUNTRIES'].include?country_code) 
        sender_id = shop.setting.sender
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
        
        customer_name = 'Customer'
        if !order_confirmation.customer_name.blank?
          customer_name = order_confirmation.customer_name
        end
        
        resp = SmsServices::Msg91SmsConfirmationService.call(
          { auth_key: shop.setting.msg91_auth_key },
          {
            flow_id: flow_id,
            sender: sender_id,
            to: phone,
            number: order_number,
            store: shop.owner_name,
            tracking_number: tracking_number,
            ur: @sms_tracking_url,
            name: customer_name
          }
        )
      elsif (ENV['WAVECELL_COUNTRIES'].include?country_code) 
        resp = SmsServices::WavecellSmsService.call(
          ENV['WAVECELL_API_KEY'],
          ENV['WAVECELL_SENDER_ID'],
        {
          to: phone,
          body: get_sms_body(order_confirmation,params,order_number),
          dlt_id: ''
        }
        )
      elsif (ENV['MOBEEP_COUNTRIES'].include?country_code) 
        resp = SmsServices::MobeepSmsService.call(
        ENV['MOBEEP_API_KEY'],
        ENV['MOBEEP_SENDER_ID'],
      {
        to: phone,
        body: get_sms_body(order_confirmation,params,order_number),
      }
      )  
      elsif (ENV['MISR_COUNTRIES'].include?country_code)
      resp = SmsServices::MisrSmsService.call(
        ENV['MISR_API_KEY'],
        ENV['MISR_SENDER_ID'],
      {
        to: phone,
        body: get_sms_body(order_confirmation,params,order_number),
      })
      elsif (ENV['VEEVOTECH_COUNTRIES'].include?country_code) 
        resp = SmsServices::VeevotechSmsService.call(
        ENV['VEEVOTECH_API_KEY'],
        ENV['VEEVOTECH_SENDER_ID'],
      {
        to: phone,
        body: get_sms_body(order_confirmation,params,order_number),
      }
      )
      else
        resp = TwilioServices::SendOtpService.new({
          from: ENV["TWILIO_PHONE_NUMBER"],
          to: phone,
          body: get_sms_body(order_confirmation,params,order_number),
          country_code: country_code,
        }).call
      end
      
      TwilioLog.create(
        sid: resp.sid,
        ver_type: 'Fulfilment-SMS',
        country_code: country_code,
        customer_number: phone,
        status: resp.sid ? 'SUCCESS' : resp.error,
        order_confirmation: order_confirmation,
        shop: shop 
      )
    rescue Exception => e
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n  *Error in fulfillment sms #{e} #{e.backtrace} #{params} "
      )
    end
      # TODO determine locking mechanism with order verification job...
    end


    def get_tracking_url(params)
      tracking_url=''
      if !params['fulfillments'].blank? && (!params['fulfillments'].first['tracking_url'].blank?)
        tracking_url = params['fulfillments'].first['tracking_url']
      end
    end

    def get_sms_body(order_confirmation,params,order_number)      
      body = order_confirmation.shop.setting.fulfilment_template

      if !order_number.blank?
        order_number = order_number.to_s
      else
        order_number = ""
      end
    
      customer_name=''
      if !order_confirmation.customer_name.blank?
        customer_name = order_confirmation.customer_name&.partition(" ")&.first
      end

      tracking_number=''
      if !params['fulfillments'].blank? && (!params['fulfillments'].first['tracking_number'].blank?)
        tracking_number = params['fulfillments'].first['tracking_number']
      end

      tracking_company=''
      if !params['fulfillments'].blank? && (!params['fulfillments'].first['tracking_company'].blank?)
        tracking_company = params['fulfillments'].first['tracking_company']
      end

      tracking_url = @sms_tracking_url.presence || get_tracking_url(params).presence || order_confirmation.order_status_url.presence || params['order_status_url']
      # total_price=''
      # if !params['total_price'].blank?
      #   total_price = params['total_price'].to_s
      # end

      body.gsub("{{name}}", customer_name)
      .gsub("{{tracking_number}}", tracking_number)
      # .gsub("{{tracking_company}}", tracking_company)
      .gsub("{{tracking_url}}", tracking_url)
      # .gsub("{{amount}}", total_price)
      .gsub("{{store}}", order_confirmation.shop.owner_name)
      .gsub("{{store_url}}", order_confirmation.shop.shopify_domain)
      .gsub("{{number}}", order_number)
    end
  end
end
