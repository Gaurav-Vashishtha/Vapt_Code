module NetworkJobs
  class SendConfirmationSmsJob < ApplicationJob
    
    # NetworkJobs::SendConfirmationSmsJob.perform_async(Shop.last.id,OrderConfirmation.last.id)

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

    def has_partial_payment_variants?(shopify_order)
      shopify_order.note_attributes.any? do |note|
        note.attributes["name"] == "partial_payment_variants"
      end
    end

    def is_new_partial_order(shopify_order)
      return false unless shopify_order.note.is_a?(String)

      shopify_order.note.downcase.include?("partial order created".downcase)
    end

    # Backfill blank recipient fields on the local record from the freshly-read
    # Shopify order, so we never send with a generic "Customer" / blank number /
    # missing status URL when the local OrderConfirmation is incomplete.
    def backfill_from_shopify_order(order_confirmation, shopify_order)
      return order_confirmation if shopify_order.blank?

      attrs = {}
      attrs[:customer_name]    = shopify_customer_name(shopify_order)    if order_confirmation.customer_name.blank?
      attrs[:customer_number]  = shopify_customer_phone(shopify_order)   if order_confirmation.customer_number.blank?
      attrs[:country_code]     = shopify_country_code(shopify_order)     if order_confirmation.country_code.blank?
      if order_confirmation.order_status_url.blank? && shopify_order.order_status_url.present?
        attrs[:order_status_url] = shopify_order.order_status_url
      end

      attrs.reject! { |_, v| v.blank? }
      order_confirmation.update(attrs) if attrs.any?
      order_confirmation
    rescue => e
      Rails.logger.warn("[send_confirmation_sms] shopify backfill failed order=#{order_confirmation&.order_id}: #{e.class}: #{e.message}")
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


    def perform(shop_id, order_id, mode='')
      shop = Shop.find(shop_id)
      if shop.setting.locked 
        return
      end
      resp = ''
      order_confirmation = OrderConfirmation.find(order_id)
      if (shop.setting.only_send_confirmation_to_cod==true && order_confirmation.status=='Non-COD') || (!order_confirmation.source_name.blank? &&  %w[ebay1 amazon].any? { |source| order_confirmation.source_name.include?(source) })
        return
      end
      shopify_order = ''
      if order_confirmation.order_id!="1234567890"
        shopify_order = get_shopify_order(order_confirmation)

        if has_partial_payment_variants?(shopify_order)
          return
        end

        fetch_and_save_order_status_url(order_confirmation,shopify_order)

        # Recover any missing recipient details (name / phone / country / status
        # URL) from the order we just read, before we branch into WhatsApp/SMS.
        order_confirmation = backfill_from_shopify_order(order_confirmation, shopify_order)

        if order_confirmation.order_status_url.blank?
          order_confirmation = fetch_and_save_order_status_url(order_confirmation, shopify_order)
        end
      end

      flow_id = shop.setting.confirmation_flow_id
      country_code = order_confirmation.country_code
      if country_code.blank?
        return
      end
      country_code = order_confirmation.country_code.upcase
      #handle exception above...
      if shop.setting.confirmation_whatsapp && (order_confirmation.order_id!="1234567890" || mode=='whatsapp')
        resp = NetworkServices::WhatsappConfirmationService.call(shop,order_confirmation, is_new_partial_order(shopify_order))
        if !shop.setting.confirmation_sms_enabled || is_new_partial_order(shopify_order)
          return
        end
        #Error handling...
      end

      if order_confirmation.twilio_logs.where(ver_type:'Confirmation-SMS').count > 0
        return
      end

      order_number = order_confirmation.customer_facing_order_number


      if shop.setting.confirmation_flow_id.blank?
        flow_id = country_code=='IN'? ENV['MSG_91_CONFIRMATION_SMS_FLOW_ID']:ENV['MSG_91_CONFIRMATION_SMS_NON_INDIA_FLOW_ID']           
      end

      if !shop.setting.provider.blank? && !shop.setting.provider_api_key.blank?
        resp = shop.setting.provider.constantize.call(
          shop.setting.provider_api_key,
          shop.setting.provider_sender_id,
          {
            to: order_confirmation.customer_number,
            body: get_sms_body(order_confirmation,order_number),
            dlt_id: ''
          }
        )
        elsif (ENV['MOVIDER_COUNTRIES'].include?country_code) 
        resp = SmsServices::MoviderSmsService.call(
          "#{ENV['MOVIDER_API_KEY']}:#{ENV['MOVIDER_API_SECRET']}",
          ENV['MOVIDER_SENDER_ID'],
        {
          to: order_confirmation.customer_number,
          body: get_sms_body(order_confirmation,order_number),
          dlt_id: ''
        }
        )
        elsif (ENV['SMS_COUNTRY_COUNTRIES'].include?country_code)  #Always keep above Msg91
        sender_id = 'BNexTECH'
        api_key = ENV['SMS_COUNTRY_BASE_64_KEY']
        # base 64 encoding for API key and token Rwid37f5wtuDfBAkbYzx:cnNsv1GYPDCdIouKj8E5Yohh6TIp6SposonpTOZ3
        params = {
          text: get_sms_body(order_confirmation,order_number),
          number:  order_confirmation.customer_number,
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
              to: order_confirmation.customer_number,
              number: order_number,
              store: shop.owner_name,
              ur: order_confirmation.order_status_url,
              name: customer_name
            }
          )
        elsif (ENV['WAVECELL_COUNTRIES'].include?country_code) 
          resp = SmsServices::WavecellSmsService.call(
            ENV['WAVECELL_API_KEY'],
            ENV['WAVECELL_SENDER_ID'],
          {
            to: order_confirmation.customer_number,
            body: get_sms_body(order_confirmation,order_number),
            dlt_id: ''
          }
          )
        elsif (ENV['MOBEEP_COUNTRIES'].include?country_code) 
          resp = SmsServices::MobeepSmsService.call(
          ENV['MOBEEP_API_KEY'],
          ENV['MOBEEP_SENDER_ID'],
        {
          to: order_confirmation.customer_number,
          body: get_sms_body(order_confirmation,order_number),
        }
        )
        elsif (ENV['MISR_COUNTRIES'].include?country_code)
        resp = SmsServices::MisrSmsService.call(
          ENV['MISR_API_KEY'],
          ENV['MISR_SENDER_ID'],
        {
          to: order_confirmation.customer_number,
          body: get_sms_body(order_confirmation,order_number),
        }) 
        elsif (ENV['VEEVOTECH_COUNTRIES'].include?country_code) 
          resp = SmsServices::VeevotechSmsService.call(
          ENV['VEEVOTECH_API_KEY'],
          ENV['VEEVOTECH_SENDER_ID'],
        {
          to: order_confirmation.customer_number,
          body: get_sms_body(order_confirmation,order_number)
        }
        ) 

        else
        resp = TwilioServices::SendOtpService.new({
          from: ENV["TWILIO_PHONE_NUMBER"],
          to: order_confirmation.customer_number,
          body: get_sms_body(order_confirmation,order_number),
          country_code: country_code,
        }).call
      end
      
      TwilioLog.create(
        sid: resp.sid,
        ver_type: 'Confirmation-SMS',
        country_code: country_code,
        customer_number: order_confirmation.customer_number,
        status: resp.sid ? 'SUCCESS' : resp.error,
        order_confirmation: order_confirmation,
        shop: shop
      )
      # TODO determine locking mechanism with order verification job...
    end

    def get_sms_body(order_confirmation,order_number)      
      body = order_confirmation.shop.setting.order_confirmation_template
    
      customer_name=''
      if !order_confirmation.customer_name.blank?
        customer_name = order_confirmation.customer_name&.partition(" ")&.first
      end

      if !order_number.blank?
        order_number = order_number.to_s
      else
        order_number = ""
      end

      body.gsub("{{name}}", customer_name)
      .gsub("{{amount}}", order_confirmation.order_amount)
      .gsub("{{store}}", order_confirmation.shop.owner_name)
      .gsub("{{store_url}}", order_confirmation.shop.shopify_domain)
      .gsub("{{number}}", order_number)
    end
  end
end
