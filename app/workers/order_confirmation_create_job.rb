class OrderConfirmationCreateJob < ApplicationJob
  include TwilioHelper
  sidekiq_options queue: 'critical'
  # OldOrderVerificationJob.perform_async( 13, '3864605753515','Hi {{link}} is verification link')
  MAX_TRIES = 5
  MAX_FREE_ORDERS = 5
  
  # shop=Shop.find(id)
  # shop.init_session
  # OrderConfirmationCreateJob.perform_async(JSON.parse(ShopifyAPI::Order.find(7392461979932).to_json).to_h, shop.id)

  
  def perform(params, shop_id)
    shop = Shop.find(shop_id)
    # COD Form (ARCHITECTURE.md F.5): an order created by the form is treated like a checkout
    # order (source_name 'codking_form'); every other order is returned unchanged.
    params = CodForm::OrderWebhookHook.normalize(params, shop)
    puts "create order confirmation  #{params}"
    lock_if_billing_not_enabled(shop)

    # DEBUG: trace every webhook-triggered run for codkingdemo so we can see
    # which branch the order takes and where the BSP cod_verification dispatch
    # is (or isn't) firing. Remove once the flow is verified end-to-end.
    dbg = (shop.shopify_domain == 'codkingdemo.myshopify.com')
    if dbg
      SlackNotifyJob.perform_async(
        ":inbox_tray: OrderConfirmationCreateJob entered (#{Rails.env}) " \
        "shop=#{shop.shopify_domain} order=#{params['id']} name=#{params['name']} " \
        "gateway=#{params['gateway'].inspect} " \
        "payment_gateway_names=#{params['payment_gateway_names'].inspect} " \
        "financial_status=#{params['financial_status'].inspect} " \
        "has_otp_note=#{Array(params['note_attributes']).any? { |a| a['name'] == '_otpVerifiedPhoneNumber' }}"
      )
    end

    if !acquire_lock(params)
      if dbg
        SlackNotifyJob.perform_async(
          ":lock: OrderConfirmationCreateJob acquire_lock FAILED (#{Rails.env}) " \
          "shop=#{shop.shopify_domain} order=#{params['id']} — duplicate webhook, exiting early"
        )
      end
      return
    end

    # Abandoned pre-order OTP draft orders: delete the shopper's open draft, or record that the
    # merchant completed one. Never raises.
    PreOrderOtpDraftJobs::OrderHook.call(shop, params)
    
    # Send receipt email if order is from COD King source
    # This will be called after order_confirmation is saved
    verified_phone = get_pre_order_otp_phone(params)
    if !verified_phone.blank?
      order_confirmation = save_pre_order_confirmation(params,shop,verified_phone)
      session_id = get_pre_order_session_id(params)
      if session_id.present?
        pre_order_otp = PreOrderOtp.find_by(device_id: session_id)
        if pre_order_otp.present?
          existing_ids = pre_order_otp.shopify_order_ids.to_s.split(",").map(&:strip)
          new_id = order_confirmation.order_id.to_s.strip
          
          #Add here logic for fetching AbandonedCart and Marking it recovered
          abandoned_carts = shop.abandoned_carts.where(checkout_id: session_id)
          if abandoned_carts.present?
            abandoned_carts.first.update(notes:'Recovered')
          end

          # BSP-created AbandonedCart rows (from Whatsapp::ScheduleAbandonedCartRemindersJob)
          # use a different checkout_id format — "otp_<pre_order_otp.id>" — keyed
          # off the OTP row id, not the device_id/session_id. Mark those Recovered
          # too so the BSP scheduler stops re-firing reminders after an order lands.
          shop.abandoned_carts
              .where(checkout_id: "otp_#{pre_order_otp.id}")
              .update_all(notes: 'Recovered')
          # Append only if new_id is not already present
          unless existing_ids.include?(new_id)
            updated_ids = (existing_ids + [new_id]).join(",")
            pre_order_otp.update(
              order_status: 'ORDER_PLACED',
              shopify_order_ids: updated_ids
            )
          else
            # Just update order_status if ID already present
            pre_order_otp.update(order_status: 'ORDER_PLACED')
          end
          
        end
      end

      # BSP COD verification — same logic as in `create_order` below. Without
      # this duplicate, OTP-verified COD orders bypass BSP entirely because
      # this branch returns before reaching `create_order`. The MSG91
      # confirmation path is suppressed for these orders when BSP handles them.
      bsp_cod_handled = false
      if !order_confirmation.blank? && order_confirmation.is_cod(params)
        bsp_binding = shop.whatsapp_template_bindings.find_by(event_type_key: 'cod_verification')
        if dbg
          SlackNotifyJob.perform_async(
            ":fork_and_knife: [OTP branch] is_cod=true (#{Rails.env}) " \
            "shop=#{shop.shopify_domain} order=#{params['id']} " \
            "binding?=#{!bsp_binding.nil?} " \
            "ready_to_send?=#{(bsp_binding&.whatsapp_account || shop.default_whatsapp_account)&.ready_to_send?}"
          )
        end
        if bsp_binding&.paused?
          bsp_cod_handled = true
        elsif bsp_binding && (bsp_binding.whatsapp_account || shop.default_whatsapp_account)&.ready_to_send?
          bsp_payload = { 'order' => params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.deep_stringify_keys : params.to_h.deep_stringify_keys }
          offset = bsp_binding.offset_minutes.to_i
          # DispatchEventJob applies the binding's offset_minutes centrally now.
          Whatsapp::DispatchEventJob.perform_async('cod_verification', shop.shopify_domain, bsp_payload)
          bsp_cod_handled = true
          if dbg
            SlackNotifyJob.perform_async(
              ":arrow_forward: [OTP branch] BSP cod_verification ENQUEUED (#{Rails.env}) " \
              "shop=#{shop.shopify_domain} order=#{params['id']} offset_minutes=#{offset}"
            )
          end
        end
      elsif dbg && !order_confirmation.blank?
        SlackNotifyJob.perform_async(
          ":fork_and_knife: [OTP branch] is_cod=FALSE — BSP skipped (#{Rails.env}) " \
          "shop=#{shop.shopify_domain} order=#{params['id']} " \
          "gateway=#{params['gateway'].inspect} " \
          "payment_gateway_names=#{params['payment_gateway_names'].inspect} " \
          "financial_status=#{params['financial_status'].inspect} " \
          "cod_include_tags=#{shop.cod_include_tags.inspect}"
        )
      end

      # Legacy (non-BSP) COD verification WhatsApp link. Sent here too, even
      # though the pre-order OTP already saved this order as COD-Verified —
      # same behaviour as the BSP dispatch above. The confirmation message is
      # then deferred to the verify endpoint (OrderConfirmationsController#confirm).
      legacy_verification_sent = false
      if !order_confirmation.blank? && !bsp_cod_handled && send_verification_whatsapp?(shop, order_confirmation, params)
        begin
          NetworkServices::WhatsappRetryService.call(shop, order_confirmation)
          order_confirmation.update(is_retried: true)
          legacy_verification_sent = true
        rescue StandardError => e
          # Never let a failed send block tagging / prepaid / lock release below.
          Rails.logger.error("[OTP branch] COD verification WhatsApp failed order=#{params['id']}: #{e.class}: #{e.message}")
        end
      end

      if !order_confirmation.blank? && !bsp_cod_handled && !legacy_verification_sent && (shop.setting.confirmation_sms_enabled || shop.setting.confirmation_whatsapp)
        NetworkJobs::SendConfirmationSmsJob.perform_async(shop.id,order_confirmation.id)
      end

      # BSP first_time_purchase — fan out via DispatchEventJob when:
      #   1. Shop has a BSP binding for first_time_purchase
      #   2. WABA account is ready to send
      #   3. The order is the customer's first (orders_count <= 1)
      # When BSP handles it, the legacy MSG91 FirstPurchaseScheduleJob is
      # suppressed for this order to avoid double-sending.
      bsp_first_purchase_handled = false
      if !order_confirmation.blank? && first_time_purchase?(params)
        bsp_fp_binding = shop.whatsapp_template_bindings.find_by(event_type_key: 'first_time_purchase')
        if bsp_fp_binding&.paused?
          bsp_first_purchase_handled = true
        elsif bsp_fp_binding && (bsp_fp_binding.whatsapp_account || shop.default_whatsapp_account)&.ready_to_send?
          bsp_fp_payload = { 'order' => params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.deep_stringify_keys : params.to_h.deep_stringify_keys }
          # DispatchEventJob applies the binding's offset_minutes centrally now.
          Whatsapp::DispatchEventJob.perform_async('first_time_purchase', shop.shopify_domain, bsp_fp_payload)
          bsp_first_purchase_handled = true
        end
      end

      if !order_confirmation.blank? && !bsp_first_purchase_handled && (shop.setting.first_purchase_whatsapp_enabled)
        NetworkJobs::FirstPurchaseScheduleJob.perform_async(shop.id,order_confirmation.id)
      end

      if !order_confirmation.blank? && shop.setting.prepaid_enabled && !rabbitpay_partial_order?(params)
        NetworkJobs::PrepaidScheduleJob.perform_async(shop.id,order_confirmation.id)
        # SlackNotifyJob.perform_async(
        #   ":rage:  (#{Rails.env})\n  *Prepaid reminder job triggered for pre order OTP"
        # )
      end
      ShopifyJobs::OrderPostJob.perform_async(shop.id, order_confirmation.id)
      release_lock(params)
      call_partial_edit_job(shop, params) # Ensure partial edit job is called for pre-order OTP flow too
      CodForm::OrderWebhookHook.after(shop, params) # COD Form F.5 (never raises)
      OrderMetrics::UpsertService.call(shop, params)
      return
    end

    
   
    if params['note'] && params['note'].present?
      @draft_order = OrderConfirmation.find_by(draft_order_uuid: params['note'])
      if @draft_order && !@draft_order.is_cod(params) # if its again placed as a COD order then treat it as normal COD order...
        process_draft_order(@draft_order, params)
      else
        create_order(params, shop)
      end
    else
      create_order(params, shop)
    end
    release_lock(params)
    call_partial_edit_job(shop,params) # call this order is created in DB...
    CodForm::OrderWebhookHook.after(shop, params) # COD Form F.5 (never raises)
    OrderMetrics::UpsertService.call(shop, params)
    OrderConfirmation.find_by(order_id: params['id'])
  rescue Exception => e
    SlackNotifyJob.perform_async(
      ":rage:  (#{Rails.env})\n  *Error* order/create webhook failure #{e.backtrace} #{e.message} \n #{params}"
    )
    release_lock(params)
    # Attempt to call partial edit job even on error, in case order was partially processed
    begin
      shop = Shop.find(shop_id) rescue nil
      call_partial_edit_job(shop, params) if shop.present?
    rescue => partial_error
      Rails.logger.error("[PartialEditJob] Error in rescue block: #{partial_error.message}")
    end
    true
  end

  def acquire_lock(params)
    Lock.new(value:params['id']).save
    true
  rescue Exception => e
    # SlackNotifyJob.perform_async(
    #   ":rage:  (#{Rails.env})\n  *Warning* OrderID locked #{params['id']}"
    # )
    false
  end


  def rabbitpay_partial_order?(params)
    Array(params['note_attributes']).any? do |attr|
      attr['name'] == '_rabbitpay_partial_order' && attr['value'].to_s.strip.casecmp?('true')
    end
  end

  def get_pre_order_otp_phone(params)
    if params['note_attributes'].present? && params['note_attributes'].size > 0
      params['note_attributes'].each do |note_attribute|
        if note_attribute['name'] == '_otpVerifiedPhoneNumber'
          return note_attribute['value']
        end
      end
    end
    return nil
  end 


  def get_pre_order_session_id(params)
    if params['note_attributes'].present? && params['note_attributes'].size > 0
      params['note_attributes'].each do |note_attribute|
        if note_attribute['name'] == '_codkSessionId'
          return note_attribute['value']
        end
      end
    end
    return nil
  end 


  # True when this order is the customer's first with the shop. Mirrors the
  # MSG91 path's check (NetworkJobs::FirstPurchaseScheduleJob:15) which uses
  # the Shopify-provided orders_count. The order webhook payload always
  # carries `customer.orders_count`, so no extra Shopify API call is needed.
  # Falls back to nil → 0 → treated as first if the field is missing (matches
  # the MSG91 path's `numberOfOrders.to_i <= 1`).
  def first_time_purchase?(params)
    return false if params.blank?
    orders_count = params.dig('customer', 'orders_count').to_i
    orders_count <= 1
  end

  def get_partial_payment_variants(params)
    partialVariantIds = ''

    # Check for note_attributes
    if params['note_attributes'].present? && params['note_attributes'].is_a?(Array)
      params['note_attributes'].each do |note_attribute|
        if note_attribute['name'] == 'partial_payment_variants'
          value = note_attribute['value']
          # Check if value is not null or the string "null"
          if value.present? && value != 'null' && value != 'NULL'
            partialVariantIds = value
            is_partial_order = true
            break
          end
        end
      end
    end
    return partialVariantIds
  end

  def call_partial_edit_job(shop, params)
    begin
      is_partial_order = false
      partialVariantIds = nil
      order_id = params["id"]
      log_pfx = "[Codk::PartialPayment]"

      # Check for note_attributes
      if params['note_attributes'].present? && params['note_attributes'].is_a?(Array)
        params['note_attributes'].each do |note_attribute|
          if note_attribute['name'] == 'partial_payment_variants'
            value = note_attribute['value']
            # Check if value is not null or the string "null"
            if value.present? && value != 'null' && value != 'NULL'
              partialVariantIds = value
              is_partial_order = true
              break
            end
          end
        end
      end
  
      # Check for line_items only if not already marked partial
      if !is_partial_order && params['line_items'].present? && params['line_items'].is_a?(Array)
        params['line_items'].each do |line_item|
          name = line_item['name'].to_s
          if name.downcase.include?("partial payment")
            is_partial_order = true
            break
          end
        end
      end

      if is_partial_order
        Rails.logger.info(
          "#{log_pfx} OrderConfirmationCreateJob enqueue PartialOrderEditJob shop_id=#{shop.id} order_id=#{order_id} " \
          "partialVariantIds=#{partialVariantIds.inspect}"
        )
        ShopifyJobs::PartialOrderEditJob.perform_async(shop.id, params['id'], partialVariantIds)
      else
        Rails.logger.info(
          "#{log_pfx} OrderConfirmationCreateJob not a partial order — skip PartialOrderEditJob order_id=#{order_id}"
        )
      end
  
    rescue => e
      Rails.logger.error("[PartialEditJob] Error processing order: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n [PartialEditJob-Order Confirmation create job] Error processing order: #{e.message}}"
      )
    end
  
    nil
  end
  

  def release_lock(params)
    Lock.find_by(value:params['id']).destroy
    true
  rescue Exception => e
    SlackNotifyJob.perform_async(
      ":rage:  (#{Rails.env})\n Unable to release lock #{params['id']}"
    )
    false
  end

  def lock_if_billing_not_enabled(shop)
    if shop.charge_id.blank? && shop.setting.sms
      persisted_setting = PersistedSetting.find_by(shopify_domain: shop.shopify_domain)
      if persisted_setting.blank?
        persisted_setting = PersistedSetting.find_or_initialize_by(
          shopify_domain: shop.shopify_domain,
          test_order_count: 1
        )
        if persisted_setting.save
          return
        end
      end
      if persisted_setting.test_order_count >= MAX_FREE_ORDERS
        shop.setting.update({locked: true, sms: false, ivr: false, status: false})
        shop.update(reviewed:false)
        WelcomeMailer.lock_shop(shop.id).deliver_later
        SlackNotifier::CLIENT.ping(
          text: ":sunglasses: *Locked Shops* (#{Rails.env}) \n #{shop.shopify_domain}",
        )
      else
        persisted_setting.update(test_order_count: (persisted_setting.test_order_count+1))
      end
    end
  end

  def process_draft_order(draft_order, params)
    if draft_order.update(status: 'COD-Prepaid', confirmed_at: Time.new)
      ShopifyJobs::OrderPostJob.perform_async(
        draft_order.shop.id, draft_order.order_id
      )
      # Build params hash for partial edit job - use partial_payment_variants from draft_order if available
      partial_params = params.dup
      if draft_order.partial_payment_variants.present?
        # Ensure note_attributes exist and include partial_payment_variants
        partial_params['note_attributes'] ||= []
        unless partial_params['note_attributes'].any? { |attr| attr['name'] == 'partial_payment_variants' }
          partial_params['note_attributes'] << {
            'name' => 'partial_payment_variants',
            'value' => draft_order.partial_payment_variants
          }
        end
      end
      call_partial_edit_job(draft_order.shop, partial_params)
    end
  end

  def create_order(params, shop)
    existing_order = OrderConfirmation.find_by(order_id: params['id'])
    if !existing_order && (params['source_name'] != 'pos')
      if shop.setting.send_verification_link_only || shop.setting.sms || shop.setting.ivr || shop.setting.partial_payment_enabled || shop.setting.cod_fee_enabled || shop.setting.prepaid_enabled || shop.setting.confirmation_sms_enabled || shop.setting.enable_fulfilment_message || shop.setting.confirmation_whatsapp || shop.setting.fulfilment_whatsapp || shop.setting.first_purchase_whatsapp_enabled || (!shop.setting.thankyou_message.blank?)
        puts "OrderID #{params['id']} contains COD for #{params['payment_gateway_names']}"
        order_confirmation = save_order_confirmation(params, shop)
        if (!shop.setting.include_countries.blank?  && (!shop.setting.include_countries.split(',').include? order_confirmation.country_code)) || (shop.setting.skip_draft_order && order_confirmation.source_name=='shopify_draft_order')
          order_confirmation.update(status: 'COD-SKIP-VERIFICATION')
          return
        end
        if !order_confirmation.blank? && shop.setting.cod_fee_enabled && order_confirmation.is_cod(params) && ((order_confirmation.source_name!='shopify_draft_order') || (order_confirmation.source_name=='shopify_draft_order' && (!shop.setting.skip_draft_order))) && !params['_codk_form']
          ShopifyServices::CodFeesService.call(
            shop,order_confirmation)
        end
        # BSP COD verification: if the shop has a `cod_verification` binding
        # and this is a COD order, dispatch the BSP path with the binding's
        # offset and suppress the MSG91 confirmation send for this order.
        # Non-COD orders fall through to the regular confirmation path.
        bsp_cod_handled = false
        dbg_create = (shop.shopify_domain == 'codkingdemo.myshopify.com')
        if !order_confirmation.blank? && order_confirmation.is_cod(params)
          bsp_binding = shop.whatsapp_template_bindings.find_by(event_type_key: 'cod_verification')
          if dbg_create
            SlackNotifyJob.perform_async(
              ":fork_and_knife: [create_order branch] is_cod=true (#{Rails.env}) " \
              "shop=#{shop.shopify_domain} order=#{params['id']} " \
              "binding?=#{!bsp_binding.nil?} " \
              "ready_to_send?=#{(bsp_binding&.whatsapp_account || shop.default_whatsapp_account)&.ready_to_send?}"
            )
          end
          if bsp_binding&.paused?
            bsp_cod_handled = true
          elsif bsp_binding && (bsp_binding.whatsapp_account || shop.default_whatsapp_account)&.ready_to_send?
            payload = { 'order' => params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.deep_stringify_keys : params.to_h.deep_stringify_keys }
            offset = bsp_binding.offset_minutes.to_i
            # DispatchEventJob applies the binding's offset_minutes centrally now.
            Whatsapp::DispatchEventJob.perform_async('cod_verification', shop.shopify_domain, payload)
            bsp_cod_handled = true
            if dbg_create
              SlackNotifyJob.perform_async(
                ":arrow_forward: [create_order branch] BSP cod_verification ENQUEUED (#{Rails.env}) " \
                "shop=#{shop.shopify_domain} order=#{params['id']} offset_minutes=#{offset}"
              )
            end
          end
        elsif dbg_create && !order_confirmation.blank?
          SlackNotifyJob.perform_async(
            ":fork_and_knife: [create_order branch] is_cod=FALSE — BSP skipped (#{Rails.env}) " \
            "shop=#{shop.shopify_domain} order=#{params['id']} " \
            "gateway=#{params['gateway'].inspect} " \
            "payment_gateway_names=#{params['payment_gateway_names'].inspect} " \
            "financial_status=#{params['financial_status'].inspect} " \
            "cod_include_tags=#{shop.cod_include_tags.inspect}"
          )
        end

        # COD orders that still need customer verification (SMS OTP, or the
        # COD verification WhatsApp link) get their confirmation message from
        # OrderConfirmationsController#confirm once the customer confirms —
        # not here at creation time.
        if !order_confirmation.blank? && !bsp_cod_handled && (shop.setting.confirmation_sms_enabled || shop.setting.confirmation_whatsapp) && (!order_confirmation.is_cod(params) || (order_confirmation.is_cod(params) && (!shop.setting.sms) && !send_verification_whatsapp?(shop, order_confirmation, params)))
          NetworkJobs::SendConfirmationSmsJob.perform_async(shop.id,order_confirmation.id)
        end
        # BSP first_time_purchase — same shape as the OTP branch above.
        bsp_first_purchase_handled = false
        if !order_confirmation.blank? && first_time_purchase?(params)
          bsp_fp_binding = shop.whatsapp_template_bindings.find_by(event_type_key: 'first_time_purchase')
          if bsp_fp_binding&.paused?
            bsp_first_purchase_handled = true
          elsif bsp_fp_binding && (bsp_fp_binding.whatsapp_account || shop.default_whatsapp_account)&.ready_to_send?
            bsp_fp_payload = { 'order' => params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.deep_stringify_keys : params.to_h.deep_stringify_keys }
            # DispatchEventJob applies the binding's offset_minutes centrally now.
            Whatsapp::DispatchEventJob.perform_async('first_time_purchase', shop.shopify_domain, bsp_fp_payload)
            bsp_first_purchase_handled = true
          end
        end

        if !order_confirmation.blank? && !bsp_first_purchase_handled && (shop.setting.first_purchase_whatsapp_enabled)
          NetworkJobs::FirstPurchaseScheduleJob.perform_async(shop.id,order_confirmation.id)
        end
        if !order_confirmation.blank? && shop.setting.prepaid_enabled && order_confirmation.is_cod(params) && !rabbitpay_partial_order?(params)
          NetworkJobs::PrepaidScheduleJob.perform_async(shop.id,order_confirmation.id)
        end
        if !order_confirmation.blank? && shop.setting.sms
          ShopifyJobs::OrderPostJob.perform_async(shop.id, order_confirmation.id)
          # When BSP already dispatched the cod_verification message for this
          # order, suppress the legacy MSG91 verification (SendSmsJob via
          # call_sms_twillio) so the customer doesn't get the same prompt twice
          # — once over BSP WhatsApp and once over MSG91. Tagging (OrderPostJob)
          # above still runs regardless.
          if order_confirmation.is_cod(params) && !bsp_cod_handled
            if shop.setting.sms
              call_sms_twillio(order_confirmation)
            else
              # call_ivr_twillio(order_confirmation, shop)
            end
          end
        else
          if order_confirmation.blank?
            puts "OrderConfirmation errors #{order_confirmation.errors}"
            SlackNotifyJob.perform_async(
                ":rage:  (#{Rails.env})\n  *Error* orders/create webhook \n Input order ID: #{params['id']}  \n Messages: #{order_confirmation.errors.messages}"
            )
          end
        end
      else
        puts "OrderID #{params['id']} does not contains COD or COD app is not enabled."
      end
    end
  end

  # True when this order gets the legacy (MSG91) COD verification WhatsApp
  # link (WhatsappRetryService). Deliberately independent of the order's
  # status: an order that is already COD-Verified still gets the message.
  # The confirmation message is then deferred to the verify endpoint.
  def send_verification_whatsapp?(shop, order_confirmation, params)
    shop.setting.send_verification_link_only &&
      order_confirmation.is_cod(params) &&
      params['source_name'] != 'shopify_draft_order'
  end

  def get_phone_from_shipping(params)
    phone_number = clean_phone_number(
      params.dig('shipping_address', 'phone'),
      params.dig('shipping_address', 'country_code').downcase
    )
  rescue StandardError => e
    phone_number = ''
  end

  def call_sms_twillio(order_confirmation)
    NetworkJobs::SendSmsJob.perform_async(
      order_confirmation.shop.id,
      order_confirmation.id
    )
  end

  def call_ivr_twillio(order_confirmation, shop)
    if !order_confirmation.customer_number.blank? && order_confirmation.notif_count < MAX_TRIES
      request = build_twiml(
        shop.primary_locale&.to_sym,
        shop.setting.ivr_introduction,
        shop.setting.ivr_confirm_message,
        shop.setting.ivr_cancel_message,
        '/twillio/ivr_webhook'
      )
      resp = TwilioServices::IvrCallService.call({
                                                   from: ENV['TWILIO_PHONE_NUMBER'],
                                                   to: order_confirmation.customer_number,
                                                   twiml: request
                                                 })
      order_confirmation.update(ivr_sid: resp.sid)
      order_confirmation.increment!(:notif_count)
      TwilioLog.create(
        sid: resp.sid,
        ver_type: 'IVR',
        country_code: order_confirmation.country_code,
        customer_number: order_confirmation.customer_number,
        status: resp.sid ? 'SUCCESS' : resp.error,
        order_confirmation: order_confirmation,
        shop: shop
      )
    else
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n  *Error* Order reached max tries order_id #{order_confirmation.order_id}"
      )
    end
  end

  def clean_phone_number(phone, country_code)
    if !phone.blank?
      phone = phone.tr('^0-9', '').sub!(/^0*/, '')
    end

    if (!country_code.blank?) && country_code.downcase==='hu' && (!phone.starts_with? '36')
      phone = '0'+phone
    end

    phone = Phonelib.parse(phone, country_code).to_s
    if !country_code.blank? && country_code.downcase=== 'ae'
      if phone.length<=9
        phone = '+971' + phone
      elsif (phone.length === 12) && (!phone.start_with? '+')
        phone= '+' + phone
      end
    end
    return phone
  rescue Exception => e
    SlackNotifyJob.perform_async(
      ":rage:  (#{Rails.env})\n *Error* Phonelib parse \n Phone: #{phone}  \n country_code: #{country_code} \n error: #{e.message}"
    )
    phone
  end

  def get_phone_from_billing(params)
    phone_number = clean_phone_number(
      params.dig('billing_address', 'phone'),
      params.dig('billing_address', 'country_code').downcase
    )
  rescue StandardError => e
    phone_number = ''
  end

  def get_phone_from_customer(params)
    phone_number = clean_phone_number(
      params.dig('customer', 'phone'),
      params.dig('customer', 'default_address', 'country_code').downcase
    )
  rescue StandardError => e
    phone_number = ''
  end

  def save_pre_order_confirmation(params, shop,verified_phone)
    
    order_confirmation = OrderConfirmation.find_or_initialize_by(order_id: params['id'], shop: shop)
    report_resave(order_confirmation, 'save_pre_order_confirmation', params)
    phone_number = verified_phone

    customer_name = if !params.dig('customer', 'first_name').blank? && !params.dig('customer', 'last_name').blank?
                      params.dig('customer', 'first_name') + ' ' + params.dig('customer', 'last_name')
                    else
                      params.dig('customer', 'first_name')
                    end
    order_cod_fee = 0
    if shop.setting.cod_fee_enabled && order_confirmation.is_cod(params)
      if shop.setting.is_percentage
        order_cod_fee = (((shop.setting.cod_fees.to_f * params['total_price'].to_f/100)*2).round ) / 2.0
      else
        order_cod_fee = shop.setting.cod_fees
      end
    end

    partial_variant_ids = get_partial_payment_variants(params)
                    
    order_status = 'COD-Verified'
    is_success = order_confirmation.update(
      order_amount: params['total_price'],
      customer_name: customer_name,
      # customer_number: params['customer']['phone'], #to check if this is right phone number...
      # this needs improvements gsub wont be suffiecient
      # user may or may not enter country code
      customer_number: phone_number,
      shop_id: shop.id,
      status: order_status,
      country_code: order_confirmation.get_country_code(params),
      ver_type: shop.get_ver_type,
      is_charged: false,
      order_number: params['order_number'],
      order_status_url: params['order_status_url'],
      customer_locale: params['customer_locale'],
      customer_id: params.dig('customer', 'id'),
      customer_email: params.dig('customer', 'email'),
      currency: params['currency'],
      shipping_address: params['shipping_address'],
      cod_fee: order_cod_fee,
      source_name: params['source_name'],
      # Never replace a code that may already be in a customer's SMS.
      persisted_otp: order_confirmation.persisted_otp.presence || OrderConfirmation.derived_otp(shop.id, params['id']),
      checkout_token: params['checkout_token'],
      is_cod_order: order_confirmation.is_cod(params),
      partial_payment_variants: partial_variant_ids,
      is_otp_verified: true
    )
    #create_prepaid(params)
    if is_success
      if order_confirmation.checkout_token.blank?
        ShopifyServices::OrderCheckoutTokenService.call(
            shop,
            order_confirmation.order_id
          )
      end
      # Send receipt email if from COD King source
      #send_email_if_cod_king_source(order_confirmation, shop)
      return order_confirmation 
    end
  end




  def save_order_confirmation(params, shop)
    order_confirmation = OrderConfirmation.find_or_initialize_by(order_id: params['id'], shop: shop)
    report_resave(order_confirmation, 'save_order_confirmation', params)
    verified_phone = get_pre_order_otp_phone(params)
    phone_number = ''
    if shop.phone_pick_order.present?
      # phone_pick_order e.g shipping,billing,customer
      shop.phone_pick_order.split(',').each do |pick_key|
        phone_number = send("get_phone_from_#{pick_key}(#{params})")
        break if phone_number.present?
      end
    else
      phone_number = get_phone_from_shipping(params)
      if !phone_number.present?
        phone_number = get_phone_from_billing(params)
      end
    end
    if verified_phone.present?
      phone_number = verified_phone
    end
    customer_name = if !params.dig('customer', 'first_name').blank? && !params.dig('customer', 'last_name').blank?
                      params.dig('customer', 'first_name') + ' ' + params.dig('customer', 'last_name')
                    else
                      params.dig('customer', 'first_name')
                    end
    order_cod_fee = 0
    if shop.setting.cod_fee_enabled && order_confirmation.is_cod(params)
      if shop.setting.is_percentage
        order_cod_fee = (((shop.setting.cod_fees.to_f * params['total_price'].to_f/100)*2).round ) / 2.0
      else
        order_cod_fee = shop.setting.cod_fees
      end
    end
                    
    order_status = order_confirmation.status
    if order_status != 'COD-Verified'
      if order_confirmation.is_cod(params) && shop.setting.sms 
        order_status = (params['source_name']=='shopify_draft_order' && shop.setting.skip_draft_order )? 'COD-SKIP-VERIFICATION' : 'Pending'
      else
        if !shop.setting.sms && shop.setting.cod_fee_enabled && order_confirmation.is_cod(params) && params['source_name']!='shopify_draft_order'
          order_status = 'COD-Fee-Applied'
        elsif shop.setting.send_verification_link_only && (!shop.setting.sms) && (!shop.setting.cod_fee_enabled) && order_confirmation.is_cod(params) && params['source_name']!='shopify_draft_order'
          order_status = 'Pending' 
        elsif shop.setting.prepaid_enabled && (!shop.setting.sms) && (!shop.setting.cod_fee_enabled)  && order_confirmation.is_cod(params)
          order_status = 'COD-Potential-Prepaid'
        elsif order_confirmation.is_cod(params)
            order_status = 'COD'
        else
          order_status = 'Non-COD'
        end 
      end
    end

    


    partial_variant_ids = get_partial_payment_variants(params)

    is_success = order_confirmation.update(
      order_amount: params['total_price'],
      customer_name: customer_name,
      # customer_number: params['customer']['phone'], #to check if this is right phone number...
      # this needs improvements gsub wont be suffiecient
      # user may or may not enter country code
      customer_number: phone_number,
      shop_id: shop.id,
      status: order_status,
      country_code: order_confirmation.get_country_code(params),
      ver_type: shop.get_ver_type,
      is_charged: false,
      order_number: params['order_number'],
      order_status_url: params['order_status_url'],
      customer_locale: params['customer_locale'],
      customer_id: params.dig('customer', 'id'),
      customer_email: params.dig('customer', 'email'),
      currency: params['currency'],
      shipping_address: params['shipping_address'],
      cod_fee: order_cod_fee,
      source_name: params['source_name'],
      # Never replace a code that may already be in a customer's SMS.
      persisted_otp: order_confirmation.persisted_otp.presence || OrderConfirmation.derived_otp(shop.id, params['id']),
      checkout_token: params['checkout_token'],
      is_cod_order: order_confirmation.is_cod(params),
      partial_payment_variants: partial_variant_ids,
      is_otp_verified: verified_phone.present?
    )
    #create_prepaid(params)
    if is_success
      if order_confirmation.checkout_token.blank?
        ShopifyServices::OrderCheckoutTokenService.call(
            shop,
            order_confirmation.order_id
          )
      end
      if send_verification_whatsapp?(shop, order_confirmation, params)
        NetworkServices::WhatsappRetryService.call(shop,order_confirmation)
        order_confirmation.update(is_retried:true)
      end
      # Send receipt email if from COD King source
      #send_email_if_cod_king_source(order_confirmation, shop)
      return order_confirmation 
    end
  end

  # The order is being saved again although it already exists — only the
  # first save should run. Its OTP is kept (see persisted_otp above), but we
  # want to know which path re-ran so it can be fixed at the source.
  def report_resave(order_confirmation, branch, params)
    return unless order_confirmation.persisted?

    caller_path = caller.select { |l| l.include?('/app/') }.first(6).map { |l| l.sub(/\A.*\/app\//, 'app/') }
    SlackNotifyJob.perform_async(
      ":warning: (#{Rails.env}) Order confirmation re-saved (OTP kept) " \
      "shop=#{order_confirmation.shop_id} order=#{params['id']} oc=#{order_confirmation.id} branch=#{branch} " \
      "status=#{order_confirmation.status} created=#{order_confirmation.created_at&.iso8601} " \
      "sms_sent=#{order_confirmation.twilio_logs.count} source=#{params['source_name'].inspect} " \
      "keys=#{params.keys.first(8).join(',')}\n```#{caller_path.join("\n")}```"
    )
  rescue StandardError => e
    Rails.logger.warn("[OrderConfirmationCreateJob] report_resave failed: #{e.message}")
  end

  def send_email_if_cod_king_source(order_confirmation, shop)
    # Skip if email was already sent
    return if order_confirmation.receipt_email_sent == true
    
    begin
      # Initialize Shopify session
      shop.init_session
      
      # Get the order from Shopify
      shopify_order = ShopifyAPI::Order.find(order_confirmation.order_id)
      
      # Check if order is from COD King source by checking for _codkSessionId in note_attributes
      # Similar to get_pre_order_session_id method
      is_cod_king_source = false
      if shopify_order.note_attributes.present? && shopify_order.note_attributes.size > 0
        shopify_order.note_attributes.each do |note_attribute|
          if note_attribute.attributes["name"] == '_codkSessionId'
            is_cod_king_source = true
            break
          end
        end
      end
      
      return unless is_cod_king_source
      
      # Set send_receipt to true
      #shopify_order.send_receipt = true
      
      # Save the order
      #shopify_order.save
      
      # Mark email as sent in order_confirmation to avoid duplicates
      order_confirmation.update(receipt_email_sent: true)
      
      Rails.logger.info("Receipt email sent for order #{order_confirmation.order_id}")
    rescue => e
      Rails.logger.error("Error sending receipt email for order #{order_confirmation.order_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      # Don't raise error to avoid breaking the order creation flow
      # Optionally notify via Slack
      SlackNotifyJob.perform_async(
        ":warning: (#{Rails.env})\n *Error* sending receipt email for order #{order_confirmation.order_id}: #{e.message}"
      )
    end
  end

  def create_prepaid(params)
    order_confirmation = OrderConfirmation.find(params['id'])
    if order_confirmation
      order_confirmation = ShopifyServices::DraftOrderCreateService.call(order_confirmation.shop, order_confirmation.id)
      if order_confirmation && order_confirmation.prepaid_link
        NetworkJobs::SendSmsJob.perform_async(
          order_confirmation.shop.id,
          order_confirmation.id
        )
        render json: order_confirmation
      else
        render json: { message: "Unable to crerate draft order for #{params[:order_id]}", error: "error" },
               status: :unprocessable_entity
      end
    else
      render json: { message: "Invalid OrderID passed #{params[:order_id]}", error: "error" },
             status: :unprocessable_entity
    end
  end


end
