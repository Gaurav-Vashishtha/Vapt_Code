class SettingsController < AuthenticatedController
  include TwilioHelper
  before_action :set_shop, only: %i[create test_otp test_ivr export export_message_logs_csv bulk_verify test_order payment_methods wallet_balance send_whatsapp_approval_request setting get_published_checkout_profile checkout_extension_editor_link product_url test_operator_sms is_cod_show_hide_enabled update_owner_phone test_payment_link]

  MAX_TEST_TRIES = 2

  # POST /settings
  # POST /settings.json
  # actually it's update
  def create
    if @shop.setting.locked
      return
      new_params = setting_params.merge!(status: false, sms: false, whatsapp: false, confirmation_sms_enabled:false, prepaid_enabled: false, enable_fulfilment_message:false,enable_pre_order_otp: false, abandoned_cart_enabled:false,ac_whatsapp:false, confirmation_whatsapp:false)
    else
      new_params = setting_params
    end
    is_metafield_refresh_needed = is_metafield_refresh_needed(new_params)
    if new_params['payment_method_name'].blank?
      new_params['payment_method_name'] = 'Cash on Delivery (COD)'
    end
    new_params['enable_pre_order_otp'] = (new_params['enable_pre_order_otp'].to_s.downcase == "true")
    
    if new_params['enable_pre_order_otp'] && new_params['country_code_list'].blank?
      render json: 'Select atleast one country', status: :unprocessable_entity
      return
    end

    # if !update_display_scope(new_params)
    #   render json: 'Unable to update Display scope', status: :unprocessable_entity
    #   return
    # end
    
    if new_params['auto_cancel'].present? && new_params['auto_cancel'].to_i!=-1 && new_params['retry'].to_i >= new_params['auto_cancel'].to_i
      render json: 'Retry time should be less than Auto cancellation time', status: :unprocessable_entity
      return
    end

    if new_params['prepaid_enabled']==true && (new_params['payment_provider_api_key'].blank? || new_params['payment_provider_api_secret'].blank?) 
      render json: 'Enter all the details (API key and Secret is mandatory to enable this setting.)', status: :unprocessable_entity
      return
    end

    if new_params['first_purchase_whatsapp_enabled']==true && (new_params['first_purchase_schedule'].blank? || new_params['first_purchase_discount_code'].blank? || new_params['first_purchase_discount_off'].blank?) 
      if new_params['first_purchase_schedule'].blank?
        new_params['first_purchase_schedule'] = 30
      end
      if new_params['first_purchase_discount_code'].blank?
        new_params['first_purchase_discount_code'] = "AppliedDiscount"
      end
      if new_params['first_purchase_discount_off'].blank?
        new_params['first_purchase_discount_off'] = "1%"
      end
      # render json: 'Enter the discount code, schedule and discount value for first time purchase notification under schedule and configure.', status: :unprocessable_entity
      # return
    end


    # if !@shop.setting.cod_variant_id.blank? && new_params['cod_fees'].to_f!=@shop.setting.cod_fees
    #   # @shop.init_session
    #   # variant = ShopifyAPI::Variant.find(@shop.setting.cod_variant_id)
    #   # variant.price = new_params['cod_fees']
    #   # if !variant.save
    #   #   render json: 'Unable to update COD fees', status: :unprocessable_entity  
    #   # end
    # end
    if !new_params['prepaid_discount'].blank?
      new_params['prepaid_discount'] = new_params['prepaid_discount'].to_f
    end
    if new_params['max_retries'] && new_params['max_retries'].to_i>5
      render json: 'Allowed limit of max retries is 5', status: :unprocessable_entity
    else
      previous_hide_shipping_method = @shop.setting.hide_shipping_method?
      hide_shipping_param_present = new_params.key?('hide_shipping_method')
      requested_hide_shipping = if hide_shipping_param_present
        ActiveModel::Type::Boolean.new.cast(new_params['hide_shipping_method'])
      else
        previous_hide_shipping_method
      end

      # Snapshot fulfilment flag state BEFORE update so we can detect a flip
      # from off → on after the save and subscribe the webhook only on that
      # transition (avoids hammering Shopify on every settings save).
      previous_fulfilment_on = @shop.setting.enable_fulfilment_message == true ||
                               @shop.setting.fulfilment_whatsapp == true

      # Snapshot BEFORE update: the services below may write to the setting
      # again, which would wipe saved_changes and hide a real merchant edit.
      previous_combines_with = @shop.setting.partial_discount_combines_with

      strip_unauthorized_prefilled_address!(new_params)
      strip_unauthorized_branding_flag!(new_params)
      strip_unauthorized_ui_customization!(new_params)
      if @shop.setting.update(new_params)
        partial_shipping_keyword_value = if new_params.key?('partial_shipping_keyword')
          new_params['partial_shipping_keyword']
        else
          @shop.setting.partial_shipping_keyword
        end

        partial_shipping_keyword_present = partial_shipping_keyword_value.present?
        reset_delivery_customization =
          hide_shipping_param_present &&
          previous_hide_shipping_method &&
          !requested_hide_shipping &&
          !partial_shipping_keyword_present
        if is_metafield_refresh_needed || reset_delivery_customization
          payment_method_name = @shop.setting.payment_method_name.presence || 'Cash on Delivery'
          payment_customization = ShopifyServices::PaymentCustomizationService.call(
            @shop , payment_method_name
          )
          delivery_customization = ShopifyServices::DeliveryCustomizationService.call(
            @shop
          )
          if payment_customization.blank?
            render json: 'Unable to create payment function ID', status: :unprocessable_entity
            return
          end
        end
        # Subscribe only when fulfilment just flipped on. add_fulfilment_webhook
        # is also idempotent (checks existing subscriptions), so even if this
        # condition slightly over-fires it won't create duplicates.
        current_fulfilment_on = @shop.setting.enable_fulfilment_message == true ||
                                @shop.setting.fulfilment_whatsapp == true
        if current_fulfilment_on && !previous_fulfilment_on
          add_fulfilment_webhook(@shop.setting)
        end
        sync_partial_discount_combines_with(@shop.setting, previous_combines_with)
        render json: @shop.setting
      else
        render json: @shop.setting.errors, status: :unprocessable_entity
      end
    end
  end


  # Only pushes discount combinations to Shopify when the merchant actually
  # flipped one of them on this save. Shops that never touch the setting never
  # get an update mutation, so their existing discount is left untouched.
  def sync_partial_discount_combines_with(setting, previous_combines_with)
    return if setting.partial_discount_combines_with == previous_combines_with

    ShopifyJobs::PartialDiscountCombinesWithSyncJob.perform_async(setting.shop_id)
  rescue => e
    Rails.logger.warn("[SettingsController] sync_partial_discount_combines_with failed shop_id=#{setting.shop_id} #{e.class}: #{e.message}")
    nil
  end

  def add_webhook(setting)
      if (setting.sms==true || setting.enable_pre_order_otp==true || setting.prepaid_enabled==true  || setting.cod_fee_enabled==true || setting.enable_shipping_cod_fees== true || setting.confirmation_sms_enabled== true ||  setting.confirmation_whatsapp==true || setting.abandoned_cart_enabled==true ||  setting.ac_whatsapp==true || setting.enable_fulfilment_message==true || setting.fulfilment_whatsapp==true)
            setting.shop.init_session
            webhook = {
            topic: 'orders/create',
            address: "https://#{ENV['APP_HOST']}/order_confirmations",
            format: 'json'
            }
            ShopifyAPI::Webhook.new(webhook).save 
      end
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

    def test_operator_sms
      if !@shop.setting.provider.blank? && !@shop.setting.provider_api_key.blank?
        resp = @shop.setting.provider.constantize.call(
          @shop.setting.provider_api_key,
          @shop.setting.provider_sender_id,
          {
            to: params[:phone],
            body: "Hello this is test SMS from COD King",
            dlt_id: @dlt_id.blank? ? @shop.setting.dlt_template_id : @dlt_id
          }
        )
        render json: { response: resp }
      else
        render json: { response: 'Operator setting missing: Please ensure to save Operator settings before testing.' }
      end
    end


    def test_notification
      type = params[:type].to_s
      mode = params[:mode].to_s
      shop = Shop.find(params[:shop_id])
      
      return render json: { error: "Shop not found" }, status: :not_found if shop.blank?
      phone =  clean_phone_number(shop.owner_phone,shop.country_code)
      case type
      when "first_time_purchase"
        order = OrderConfirmation.create!(
          order_id: "1234567890",
          order_amount: "999.00",
          customer_name: shop.shop_owner,
          customer_number: phone,
          status: "Test-Order",
          shop: shop,
          country_code: shop.country_code,
          ver_type: "sms",
          persisted_otp: "1234",
          order_status_url: shop.shopify_domain
        )
        NetworkServices::WhatsappFirstPurchaseService.call(shop,order.id)

      when "order_confirmation"
        order = OrderConfirmation.create!(
          order_id: "1234567890",
          order_amount: "999.00",
          customer_name: shop.shop_owner,
          customer_number: phone,
          status: "Test-Order",
          shop: shop,
          country_code: shop.country_code,
          ver_type: "sms",
          persisted_otp: "1234",
          order_status_url: shop.shopify_domain
        )
    
        if mode == "sms"
          NetworkJobs::SendConfirmationSmsJob.perform_async(shop.id, order.id,mode)
        elsif mode == "whatsapp"
          NetworkServices::WhatsappConfirmationService.call(shop, order)
        end
    
      when "order_fulfilment"
        order = OrderConfirmation.create!(
          order_id: "9999999999",
          order_amount: "999.00",
          customer_name: shop.shop_owner,
          customer_number: phone,
          status: "Test-Order",
          shop: shop,
          country_code: shop.country_code,
          order_status_url: shop.shopify_domain
        )
    
        if mode == "sms"
          params_obj = {
            "id" => order.order_id,
            "order_number" => "#1234",
            "order_status_url" => order.order_status_url,
            "total_price" => "999.00",
            "customer" => {
              "phone" => phone,
              "default_address" => { "phone" => order.customer_number, "country_code" => order.country_code }
            },
            "shipping_address" => {
              "name" => shop.shop_owner,
              "phone" => phone,
              "country_code" => shop.country_code
            },
            "billing_address" => {
              "phone" => phone,
              "country_code" => order.country_code
            },
            "fulfillments" => [
              {
                "tracking_number" => "TRACK123456",
                "tracking_url" => shop.shopify_domain,
                "tracking_company" => "Delhivery"
              }
            ]
          }
          NetworkJobs::SendFulfilmentSmsJob.new.perform(params_obj, shop.id,mode)
        elsif mode == "whatsapp"
          NetworkServices::WhatsappFulfilmentService.call(shop, order, order.order_status_url)
        end
    
      when "abandoned_checkout"
        cart = AbandonedCart.create!(
          checkout_id: "chk_123",
          url: shop.shopify_domain,
          phone: phone,
          country_code: shop.country_code,
          shopify_created_at: "2025-05-25T15:00:00Z",
          notif_type: mode,
          is_charged: false,
          shop: shop,
          total_price: 999.0,
          name: shop.shop_owner,
          scheduled_at: Time.current + 1.hour,
          featured_image: "https://cdn.shopify.com/s/files/1/0655/2089/4070/files/Main_b13ad453-477c-4ed1-9b43-81f3345adfd6.jpg?v=1756710198"
        )
    
        if mode == "sms"
          NetworkServices::AbandonedSendSmsService.call(cart.id, shop.setting.abandoned_template, '', true)
        elsif mode == "whatsapp"
          NetworkServices::WhatsappAbandonService.call(shop, cart)
        end
    
      when "cod_verification"
        order = OrderConfirmation.create!(
          order_id: "8888888888",
          order_amount: "999.00",
          customer_name: shop.shop_owner,
          customer_number: phone,
          status: "Test-Order",
          shop: shop,
          country_code: shop.country_code,
          ver_type: "whatsapp",
          persisted_otp: "1234",
          order_status_url: shop.shopify_domain
        )
        
        if mode == "whatsapp"
          NetworkServices::WhatsappRetryService.call(shop, order)
        end
    
      else
        return render json: { error: "Invalid type: #{type}" }, status: :bad_request
      end
    
      render json: { success: true, type: type, mode: mode, number: (order&.customer_number || cart&.phone) }
    
    rescue => e
      render json: { error: e.message, backtrace: e.backtrace.take(3) }, status: :internal_server_error
    end
    
    

  # Legacy entry point — delegates to the shared service. Only subscribes when
  # the merchant has fulfilment SMS or fulfilment WhatsApp on. The BSP path
  # (TemplateBindingsController) also calls the service directly when an
  # `order_fulfilled` automation is activated.
  def add_fulfilment_webhook(setting)
    return unless setting.enable_fulfilment_message == true || setting.fulfilment_whatsapp == true
    ShopifyServices::FulfilmentWebhookSubscribeService.call(setting.shop)
  end

  def update_display_scope(new_params)
    if new_params['enable_pre_order_otp']!=@shop.setting.enable_pre_order_otp
      display_scope = 'order_status'
      if !new_params['enable_pre_order_otp'].blank? && new_params['enable_pre_order_otp'].to_s=='true'
        display_scope='all'
      end
      @shop.init_session
      first_script_tag = ShopifyAPI::ScriptTag.all.first
      if first_script_tag
        st = ShopifyAPI::ScriptTag.find(ShopifyAPI::ScriptTag.all.first.id)
        st.display_scope=display_scope
        return st.save
      else
        return true
      end
    end
    return true
  end


  #enable pre order
  #cod_label
  def is_metafield_refresh_needed(new_params)
    partial_shipping_keyword_value = if new_params.key?('partial_shipping_keyword')
      new_params['partial_shipping_keyword']
    else
      @shop.setting.partial_shipping_keyword
    end
    partial_shipping_keyword_present = partial_shipping_keyword_value.present?

    hide_shipping_change_requires_refresh = if new_params.key?('hide_shipping_method')
      requested_hide_shipping = ActiveModel::Type::Boolean.new.cast(new_params['hide_shipping_method'])
      requested_hide_shipping != @shop.setting.hide_shipping_method && !partial_shipping_keyword_present
    else
      false
    end

    return ((new_params['payment_method_name']!=@shop.setting.payment_method_name) && (!new_params['payment_method_name'].blank? || !@shop.setting.payment_method_name.blank?)) ||
      ((new_params['excluded_zips']!=@shop.setting.excluded_zips)  && (!new_params['excluded_zips'].blank? || !@shop.setting.excluded_zips.blank?)) || 
      ((new_params['phone_numbers']!=@shop.setting.phone_numbers) && (!new_params['phone_numbers'].blank? || !@shop.setting.phone_numbers.blank?))  ||
      ((new_params['enable_pre_order_otp']!=@shop.setting.enable_pre_order_otp) && (!new_params['enable_pre_order_otp'].blank? || !@shop.setting.enable_pre_order_otp.blank?)) ||
      ((new_params['selected_zips']!=@shop.setting.selected_zips) && (!new_params['selected_zips'].blank? || !@shop.setting.selected_zips.blank?))  || 
      ((new_params['selected_product_ids']!=@shop.setting.selected_product_ids) && (!new_params['selected_product_ids'].blank? || !@shop.setting.selected_product_ids.blank?))  || 
      ((new_params['selected_countries']!=@shop.setting.selected_countries) && (!new_params['selected_countries'].blank? || !@shop.setting.selected_countries.blank?))  ||  
      (new_params['hide_delivery_method']!=@shop.setting.hide_delivery_method && (!new_params['hide_delivery_method'].blank? || !@shop.setting.hide_delivery_method.blank?))  || 
      ((new_params['min_cart_total'].to_f!=@shop.setting.min_cart_total.to_f) && (!new_params['min_cart_total'].blank? || !@shop.setting.min_cart_total.blank?))  || 
      ((new_params['max_cart_total'].to_f!=@shop.setting.max_cart_total.to_f) && (!new_params['max_cart_total'].blank? || !@shop.setting.max_cart_total.blank?))  || 
      (new_params['cod_fee_enabled']!=@shop.setting.cod_fee_enabled && (!new_params['cod_fee_enabled'].blank? || !@shop.setting.cod_fee_enabled.blank?))  || 
      (new_params['cod_label']!=@shop.setting.cod_label && (!new_params['cod_label'].blank? || !@shop.setting.cod_label.blank?))  || 
      (new_params['excluded_shipping_methods']!=@shop.setting.excluded_shipping_methods && (!new_params['excluded_shipping_methods'].blank? || !@shop.setting.excluded_shipping_methods.blank?))  || 
      (new_params['show_provinces']!=@shop.setting.show_provinces && (!new_params['show_provinces'].blank? || !@shop.setting.show_provinces.blank?))  || 
      (new_params['hide_provinces']!=@shop.setting.hide_provinces && (!new_params['hide_provinces'].blank? || !@shop.setting.hide_provinces.blank?))  || 
      (new_params['cod_fee_shipping_keyword']!=@shop.setting.cod_fee_shipping_keyword && (!new_params['cod_fee_shipping_keyword'].blank? || !@shop.setting.cod_fee_shipping_keyword.blank?))  ||
      (new_params['cod_only_shipping_keyword']!=@shop.setting.cod_only_shipping_keyword && (!new_params['cod_only_shipping_keyword'].blank? || !@shop.setting.cod_only_shipping_keyword.blank?))  ||
      (new_params['enable_shipping_cod_fees']!=@shop.setting.enable_shipping_cod_fees && (!new_params['enable_shipping_cod_fees'].blank? || !@shop.setting.enable_shipping_cod_fees.blank?))  || 
      (new_params['hide_product_variant_ids']!=@shop.setting.hide_product_variant_ids && (!new_params['hide_product_variant_ids'].blank? || !@shop.setting.hide_product_variant_ids.blank?))  ||
      (new_params['show_product_ids']!=@shop.setting.show_product_ids && (!new_params['show_product_ids'].blank? || !@shop.setting.show_product_ids.blank?))  ||
      ((new_params['hide_discount_total'].to_f!=@shop.setting.hide_discount_total.to_f) && (!new_params['hide_discount_total'].blank? || !@shop.setting.hide_discount_total.blank?))  ||
      (new_params['email_addresses']!=@shop.setting.email_addresses && (!new_params['email_addresses'].blank? || !@shop.setting.email_addresses.blank?))  ||
      (new_params['hide_gift_cards']!=@shop.setting.hide_gift_cards && (!new_params['hide_gift_cards'].blank? || !@shop.setting.hide_gift_cards.blank?))  ||
      (new_params['hide_vendors']!=@shop.setting.hide_vendors && (!new_params['hide_vendors'].blank? || !@shop.setting.hide_vendors.blank?))  ||
      (new_params['show_vendors']!=@shop.setting.show_vendors && (!new_params['show_vendors'].blank? || !@shop.setting.show_vendors.blank?))  ||
      (new_params['partial_shipping_keyword']!=@shop.setting.partial_shipping_keyword && (!new_params['partial_shipping_keyword'].blank? || !@shop.setting.partial_shipping_keyword.blank?)) ||
      (new_params['excluded_collection_ids']!=@shop.setting.excluded_collection_ids && (!new_params['excluded_collection_ids'].blank? || !@shop.setting.excluded_collection_ids.blank?)) ||
      (new_params['selected_collection_ids']!=@shop.setting.selected_collection_ids && (!new_params['selected_collection_ids'].blank? || !@shop.setting.selected_collection_ids.blank?)) ||
      (new_params['partial_payment_enabled']!=@shop.setting.partial_payment_enabled && (!new_params['partial_payment_enabled'].blank? || !@shop.setting.partial_payment_enabled.blank?)) ||
      (new_params['hide_for_unverified_orders'] != @shop.setting.hide_for_unverified_orders && (!new_params['hide_for_unverified_orders'].blank? || !@shop.setting.hide_for_unverified_orders.blank?)) ||
      (new_params['google_conversion_id'] != @shop.setting.google_conversion_id && (!new_params['google_conversion_id'].blank? || !@shop.setting.google_conversion_id.blank?)) ||
      hide_shipping_change_requires_refresh
  end

  def provinces
    country_code = params['countryCode']
    if country_code.blank?
      render json: {provinces: Province.all}
    else
      render json: {provinces: Province.where(country_code: country_code)}
    end
  end

  def is_cod_show_hide_enabled
      render json: {isCodShowHideEnabled: @shop.setting.is_cod_show_hide_enabled?}
  end

  # GET /settings/local_providers?country_code=TH
  def local_providers
    country_code = params[:country_code]&.upcase
    
    if country_code.blank?
      render json: { providers: [], error: "Country code is required" }, status: :bad_request
      return
    end

    mappings = SmsProviderCountryMapping.providers_for_country(country_code)
    
    # Map to provider info with label and value
    # Match labels with frontend NetworkSettingTab providers array
    provider_label_map = {
      "SmsServices::TwilioSmsService" => "Twilio (Global)",
      "SmsServices::WavecellSmsService" => "Wavecell (Global)",
      "WhatsappServices::ChatapiWhatsappService" => "Chat API (Whatsapp Global)",
      "SmsServices::SmsshareSmsService" => "ProWebSms (Smshare) (Global)",
      "SmsServices::VeevotechSmsService" => "Veevotech (Pakistan)",
      "SmsServices::BrandedSmsService" => "Branded SMS (Pakistan)",
      "SmsServices::IsmartSmsService" => "iSmart (Oman)",
      "SmsServices::WinsmsproSmsService" => "Winsmspro (Tunisia)",
      "SmsServices::ESmsService" => "eSMS (Vietnam)",
      "SmsServices::PalPigeonSmsService" => "PalPigeon (Turkey)",
      "SmsServices::MoviderSmsService" => "Movider (Philippines)",
      "SmsServices::BoomcastSmsService" => "BoomCast (Bangladesh)",
      "SmsServices::MisrSmsService" => "SmsMisr (Egypt)",
      "SmsServices::ThaiSmsService" => "ThaiBulkSMS (Thailand)",
      "SmsServices::BulkSmsBdService" => "BulkSmsBdService (Bangladesh)"
    }
    
    # Helper to normalize provider name and find full class name
    # Try to match partial provider names to full service class names
    normalize_provider = lambda do |provider_name|
      # If it's already a full class name, return as is
      return provider_name if provider_label_map.key?(provider_name)
      
      # Try to find by exact or close match (e.g., "Movider" -> "SmsServices::MoviderSmsService")
      provider_label_map.keys.each do |full_name|
        # Extract service name from full class name (e.g., "Movider" from "SmsServices::MoviderSmsService")
        service_name = full_name.split('::').last.gsub('SmsService', '').gsub('WhatsappService', '').gsub('Service', '')
        
        # Exact match: "Movider" == "Movider"
        if service_name.downcase == provider_name.downcase
          return full_name
        end
        
        # Check if full class name contains the provider name as a whole word
        # This handles cases like "Movider" matching "SmsServices::MoviderSmsService"
        # Use word boundary matching to avoid false positives (e.g., "movider" containing "e")
        if provider_name.length >= 3 && full_name.downcase.include?(provider_name.downcase)
          # Additional check: make sure it's not just a single character match
          # Check if the service name starts with the provider name or vice versa
          if service_name.downcase.start_with?(provider_name.downcase) || 
             provider_name.downcase.start_with?(service_name.downcase)
            return full_name
          end
        end
      end
      
      # If no match found, return original (will use fallback label)
      provider_name
    end
    
    providers = mappings.map do |mapping|
      normalized_provider = normalize_provider.call(mapping.provider)
      label = provider_label_map[normalized_provider] || 
              normalized_provider.split('::').last.gsub('SmsService', '').gsub('WhatsappService', '').gsub('Service', '')
      {
        provider: normalized_provider,
        label: label,
        supported_countries: mapping.country_codes
      }
    end

    render json: { 
      providers: providers,
      country_code: country_code,
      count: providers.length
    }
  end

  def wallet_balance
    wallet = Wallet.find_by(shopify_domain:@shop.shopify_domain)
    render json: {wallet: wallet}
  end

  def product_url
    begin
      product_url = ShopifyServices::ProductGetService.call(@shop)
      
      if product_url.nil?
        render json: { error: true, message: 'No active products found' }, status: :not_found
      else
        render json: { product_url: product_url }
      end
    rescue => e
      Rails.logger.error "Error fetching product URL: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: true, message: 'Failed to fetch product URL' }, status: :internal_server_error
    end
  end

  def branded_whatsapp_templates
    shop_id = params['shop_id']
    if shop_id.blank?
      render json: 'ShopID cant be blank', status: :unprocessable_entity
      return
    end
    render json: {data:BrandedWhatsappTemplate.where(shop_id:shop_id)}
  end

  def save_branded_whatsapp_template
    puts 'params'
    shop_id = JSON.parse(params['shop'].to_json).to_h['id']
    shop = shop_id && Shop.find(shop_id)
    if shop
      branded_template = BrandedWhatsappTemplate.find_or_initialize_by(shop_id:shop.id,template_type:params['message_type'])
      branded_template.update(template_name:params['template_name'],variables:params['variable_values'].join(":"),language:params['language'])
    end
  end

  def payment_methods
       render json: {payment_methods: ShopifyServices::PaymentMethodGetService.call(@shop)}
  end

  def export
    job_id = WelcomeMailer.send_csv(@shop.id).deliver_later
    if job_id
      render json: { job_id: job_id }
    else
      render json: { error: true }
    end
  end

  def get_published_checkout_profile
    published_profile = ShopifyServices::CheckoutProfileGetService.call(@shop)
    if published_profile==false
      render json: {error: true}
    else
      render json: {checkout_profile: published_profile}
    end
  end

  # Shopify Admin deep link to Checkout Editor (Payment step) for the published checkout profile.
  def checkout_extension_editor_link
    published_profile = ShopifyServices::CheckoutProfileGetService.call(@shop)
    if published_profile == false || published_profile[:id].blank?
      render json: { error: true, message: "Unable to resolve published checkout profile" }, status: :unprocessable_entity
      return
    end

    shop_handle = @shop.shopify_domain.to_s.sub(/\.myshopify\.com\z/, "")
    profile_id = published_profile[:id].to_s
    url = "https://admin.shopify.com/store/#{shop_handle}/settings/checkout/editor/profiles/#{profile_id}?page=checkout"
    render json: {
      url: url,
      profile_id: profile_id,
      shop_handle: shop_handle
    }
  end

  def export_message_logs_csv
    days = params[:days].to_i.presence || 30
    job_id = WelcomeMailer.send_message_logs_csv(@shop.id,days).deliver_later
    if job_id
      render json: { job_id: job_id }
    else
      render json: { error: true }
    end
  end

  def send_whatsapp_approval_request
    @shop.setting.update(whatsapp_approval_status: "requested")
    if @shop.setting.approved?
      render json: { auto_approved: true, setting: @shop.setting }
      return
    end
    @shop.setting.update(whatsapp_approval_notes: "Whatsapp approval request sent")
    job_id = WelcomeMailer.send_whatsapp_approval_request(@shop.id).deliver_later
    if job_id
      render json: { job_id: job_id, setting: @shop.setting }
    else
      render json: { error: true }
    end
  end

  def setting
    render json: { shopId: @shop.id, setting: @shop.setting }
  end

  def bulk_verify
    err_ids = []
    job_ids = []
    order_ids = params[:order_ids]
    order_ids.split(",").each_with_index do |order_id, index|
      job_id = OldOrderVerificationJob.perform_in((index + 1) * 3.seconds, @shop.id, order_id.strip, params[:template])
      if job_id
        job_ids.push(job_id)
      else
        err_ids.push(order_id)
      end
    end
    if err_ids.empty?
      render json: { job_id: job_ids.join(",") }
    else
      render json: { error: err_ids.join(",") }
    end
  end

  def get_sms_share_token
    resp = HTTParty.post("https://smshare.fr/api/v2/access-token",
                         body: {
                           login: params[:login],
                           password: params[:password],
                           apiKey: "50f40d54-9a69-4952-95c5-f5346c0cc8e8",
                           appName: "COD King",
                         }.to_json,
                         headers: {
                           "Content-Type" => "application/json",
                         })
    render json: resp
  end

  def test_otp
    resp = send_sms
    if resp&.sid
      render json: { sid: resp.sid }
    else
      render json: { sid: resp.sid, error: resp.error }, status: :unprocessable_entity
    end
  end

  def test_order
    if !@shop.setting.sms
      @shop.setting.update(sms:true)
    end
    if @shop.setting.test_variant_id.blank?
      resp = ShopifyServices::CodfeeProductCreateService.call(@shop, 'COD-King-Test-Product', 5.0)
      resp_hash = JSON.parse(resp.to_json).to_h
      variant_id = resp_hash['variant_id']
      @shop.setting.test_variant_id = variant_id

      @shop.setting.save
      # ShopifyServices::CodProductCreateService.call(@shop,5.0,true)
    end
    li = [{"variant_id":@shop.setting.test_variant_id,"quantity":1}]
    shipping_address_obj =  {
      "address1": "COD King St",
      "address2": "",
      "city": "Ottawa",
      "country": "Canada",
      "first_name": "John",
      "last_name": "Doe",
      "province": "Ontario",
      "zip": "K2P0V6",
      "country_code": @shop.country_code,
      "province_code": "ON",
      "phone": @shop.owner_phone
    }
    order = ShopifyAPI::Order.new(line_items: li, shipping_address: shipping_address_obj)
    if order.save
      OrderConfirmationCreateJob.perform_async(JSON.parse(order.to_json).to_h, @shop.id)
      @shop.setting.update(test_order_url: order.order_status_url)
      render json: { url: order.order_status_url }
    else
      render json: { error: 'Error' }, status: :unprocessable_entity
      SlackNotifyJob.perform_async(
        ":rage:  (#{Rails.env})\n *Error* creating test order #{order}"
      )
    end
  end

  def test_payment_link
    result = NetworkServices::PaymentProviderTestService.call(
      @shop,
      provider: params[:provider],
      api_key: params[:api_key],
      api_secret: params[:api_secret]
    )
    render json: {
      ok: result.ok,
      provider: result.provider,
      link: result.link,
      mode: result.mode,
      message: result.message
    }, status: (result.ok ? :ok : :unprocessable_entity)
  end

  def test_ivr
    # resp = place_ivr_call
    # if resp&.sid
    #   render json: { sid: resp.sid }
    # else
    #   render json: { sid: resp.sid, error: resp.error }, status: :unprocessable_entity
    # end
  end

  def create_prepaid
    order_confirmation = OrderConfirmation.find(params[:order_id])
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

  # POST /settings/update_owner_phone — store owner phone used for test SMS/WhatsApp (see test_notification).
  def update_owner_phone
    # @shop is nil unless this action is in before_action :set_shop above; also resolve domain like ApplicationController#get_domain.
    unless @shop
      domain = current_shopify_domain.presence || params[:shop].presence || params[:domain].presence
      @shop = Shop.find_by_shopify_domain_with_cache(domain) if domain.present?
    end
    unless @shop
      return render json: { error: "Shop not found" }, status: :not_found
    end

    if params[:shop_id].to_i != @shop.id
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    raw = params[:owner_phone].to_s.strip
    if raw.blank?
      return render json: { error: "Phone number is required" }, status: :unprocessable_entity
    end

    normalized = clean_phone_number(raw, @shop.country_code)
    @shop.owner_phone = normalized
    if @shop.save
      render json: {
        success: true,
        owner_phone: @shop.owner_phone,
        number: normalized,
      }
    else
      render json: { error: @shop.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  # Only allow a list of trusted parameters through.
  def setting_params
    params.require(:setting).permit(
      :id, :status, :sms , :whatsapp, :ivr, :ivr_introduction, :ivr_confirm_message, :ivr_cancel_message,
      :max_retries, :otp_wait_time, :otp_fallback_text, :auto_verify, :show_cancel_button,
      :provider, :provider_api_key, :provider_sender_id, :cod_fee_enabled,
      :cod_fees, :cod_label, :cod_description, :cod_instrutction, :is_checkout_done, :auto_cancel, :is_shipping_phone_done, 
      :is_cod_fee_checkout_done, :is_cod_fee_email_done, :retry, :is_percentage, :cancel_notif_enabled, :custom_script, :auto_delete,
      :payment_method_name, :min_cart_total, :max_cart_total, :abandoned_cart_enabled, :shipping_cost, :hide_delivery_method, :selected_countries, :selected_zips,
      :selected_product_ids, :enable_pre_order_otp, :phone_numbers, :excluded_zips,:pre_heading,:pre_sub_heading,:pre_send_button_label,
      :pre_verify_button_label,:pre_proceed_button_label,:pre_invalid_otp_msg,:pre_success_message, :country_code_list,:confirmation_sms_enabled, :pre_skip_btn_text, :pre_redirect_text,
      :pre_show_skip_btn, :enable_fulfilment_message, :prepaid_enabled, :prepaid_amount_type,
      :prepaid_token_amount, :prepaid_discount_type, :prepaid_discount, :payment_provider, :payment_provider_api_key, :payment_provider_api_secret, :bsp_prepaid_template_id,
      :prepaid_heading, :prepaid_sub_heading, :prepaid_banner_color, :pre_primary_button_color, :pre_secondary_button_color, :pre_primary_button_font_color,:pre_secondary_button_font_color,
      :ac_whatsapp, :whatsapp_enabled, :excluded_shipping_methods, :pre_whatsapp_button, :pre_whatsapp_button_text, :ac_whatsapp_schedule, :ac_sms_schedule,
      :show_provinces,:hide_provinces, :cod_fee_shipping_keyword, :cod_only_shipping_keyword, :enable_shipping_cod_fees, :hide_product_variant_ids, :confirmation_whatsapp, :fulfilment_whatsapp, 
      :ac_whatsapp_discount, :ac_whatsapp_discount_code, :ac_whatsapp_discout_enabled, :prepaid_schedule, :post_order_include_product_ids,
      :otp_ext_heading,:otp_ext_enter_otp_sent_on,:otp_ext_sending_otp,:otp_ext_enter_otp,:otp_ext_resend_otp_in,:otp_ext_resend_otp,:otp_ext_get_code_in_whatsapp,
      :otp_ext_verify_otp, :otp_ext_successful, :otp_ext_change,:otp_ext_submit,
      :first_purchase_whatsapp_enabled,
      :first_purchase_schedule,
      :first_purchase_discount_code, 
      :first_purchase_discount_off,
      :whatsapp_operator_config,
      :branded_whatsapp_number,
      :show_product_ids, :hide_shipping_method, :hide_for_unverified_orders,
      :is_prefilled_address_enabled,
      :pre_phone_placeholder, 
      :pre_invalid_phone, 
      :pre_verify_mobile,
      :pre_enter_code, 
      :pre_retry_in, 
      :pre_resend, 
      :pre_failed_to_verify, 
      :pre_verifying, 
      :pre_too_many,
      :pre_is_new_design_enabled,
      :pre_v2_title,
      :pre_is_login_enabled,
      :pre_v2_theme,
      :pre_v2_show_order_summary,
      :partial_payment_enabled,
      :hide_discount_total,
      :email_addresses,
      :hide_gift_cards,
      :hide_vendors,
      :show_vendors,
      :pre_block_phone,
      :is_tax_included_with_product,
      :selected_locale,
      :pre_email_mandatory,
      :partial_shipping_keyword,
      :excluded_collection_ids,
      :selected_collection_ids,
      :pre_geo_countries,
      :partial_payment_flow,
      :pre_v2_show_send_code,
      :pre_v2_partial_tax_text,
      :pre_v2_no_rule_qualified_message,
      :pre_show_branding,
      :brand_logo_url,
      :quick_onboarding_visited,
      :user_journey,
      :send_verification_link_only,
      :verification_tag,
      :whatsapp_language_code,
      :whatsapp_order_confirmation_template,
      :whatsapp_first_purchase_template,
      :whatsapp_abandoned_cart_template,
      :whatsapp_fulfilment_template,
      :whatsapp_cod_verification_template,
      :promo_banner_show,
      :promo_banner_text,
      :promo_banner_color,
      :promo_text_color,
      :cod_form_enabled,
      :pre_v2_show_tax_info,
      :pre_v2_show_shipping_info,
      :include_shipping_in_payment_options,
      :plus_checkout_otp_extension_enabled,
      :revert_discount,
      :pixel_id,
      :pixel_token,
      :pixel_test_event_id,
      :conversion_tracking,
      :meta_events_enabled,
      :persistent_signin,
      :google_conversion_id,
      :google_conversion_label,
      :google_conversion_token,
      :show_offer_and_reward,
      :optimized_buy_now,
      :partial_discount_combines_with_order,
      :partial_discount_combines_with_product,
      :partial_discount_combines_with_shipping,
      private_payment_provider: {},
      cod_form_config: {},
      ui_customization: {}
    )
  end

  # Prefilled shipping is paid-plan only; drop enable attempts from free shops so the flag stays unchanged.
  def strip_unauthorized_prefilled_address!(params_hash)
    return unless params_hash.key?("is_prefilled_address_enabled")

    wants = ActiveModel::Type::Boolean.new.cast(params_hash["is_prefilled_address_enabled"])
    return unless wants

    paid = @shop.charge_id.present? && @shop.plan&.name.to_s.downcase != "free"
    params_hash.delete("is_prefilled_address_enabled") unless paid
  end

  # Removing the COD King mark is Pro and above. pre_show_branding hides it just
  # as hide_footer_branding does, so it needs the same gate: the editor disables
  # the switch, but without this the paid feature is one plain column away.
  # Turning the mark back on is always allowed.
  def strip_unauthorized_branding_flag!(params_hash)
    return unless params_hash.key?("pre_show_branding")
    return if UiCustomizationPlanGuard.branding_allowed_for?(@shop)

    hiding = ActiveModel::Type::Boolean.new.cast(params_hash["pre_show_branding"]) == false
    params_hash.delete("pre_show_branding") if hiding
  end

  # Checkout copy, widget_visibility and the footer terms/privacy links are
  # available on every plan. Removing the COD King mark is not, so a shop below
  # Pro keeps whatever hide_footer_branding it saved earlier (a downgrade must
  # not destroy it) but cannot write a new value.
  def strip_unauthorized_ui_customization!(params_hash)
    return unless params_hash.key?("ui_customization")
    return if UiCustomizationPlanGuard.branding_allowed_for?(@shop)

    incoming = params_hash["ui_customization"]
    incoming = incoming.to_h if incoming.respond_to?(:to_h)
    return unless incoming.is_a?(Hash)
    return unless incoming.key?("branding")

    stored = @shop.setting[:ui_customization]
    stored = {} unless stored.is_a?(Hash)

    gated = UiCustomizationPlanGuard::GATED_BRANDING_KEYS
    incoming_branding = incoming["branding"]
    incoming_branding = incoming_branding.to_h if incoming_branding.respond_to?(:to_h)
    incoming_branding = {} unless incoming_branding.is_a?(Hash)
    stored_branding = stored["branding"]
    stored_branding = {} unless stored_branding.is_a?(Hash)

    branding = incoming_branding.stringify_keys.except(*gated)
      .merge(stored_branding.stringify_keys.slice(*gated))

    kept = incoming.except("branding")
    kept["branding"] = branding if branding.present?

    # A bare Hash assigned into ActionController::Parameters comes back out as
    # an unpermitted nested Parameters and blows up the later update.
    params_hash["ui_customization"] =
      if params_hash.is_a?(ActionController::Parameters)
        ActionController::Parameters.new(kept).permit!
      else
        kept
      end
  end

  def place_ivr_call
    if @shop.test_notif_count <= MAX_TEST_TRIES
      request = build_twiml(
        @shop.primary_locale&.to_sym,
        params[:ivr_introduction],
        params[:ivr_confirm_message],
        params[:ivr_cancel_message]
      )
      resp = TwilioServices::IvrCallService.call({
                                                   from: ENV["TWILIO_PHONE_NUMBER"],
                                                   to: params[:customer_number],
                                                   twiml: request,
                                                 })
      @shop.increment!(:test_notif_count)
      resp
    else
      SlackNotifier::CLIENT.ping(
        text: ":rage: Send Test IVR (#{Rails.env})\n *Error* reached max test tries",
      )
      OpenStruct.new({
                       sid: nil,
                       error: I18n.t("admin.free_limit_exhausted"),
                     })
    end
  end

  

  def send_sms
    if @shop.setting.provider.blank? || @shop.setting.provider_api_key.blank?
      return render json: {}, status: :unprocessable_entity
    end
    if !@shop.setting.provider.blank? && !@shop.setting.provider_api_key.blank?
      resp = @shop.setting.provider.constantize.call(
        @shop.setting.provider_api_key,
        @shop.setting.provider_sender_id,
        {
          to: params[:customer_number],
          body: get_sms_body,
          dlt_id: @shop.setting.dlt_template_id
        }
      )
    elsif @shop.test_notif_count < MAX_TEST_TRIES
      if @shop.country_code == 'IN'
        resp = SmsServices::Msg91SmsService.call(
          { auth_key: ENV['MSG91_AUTHKEY'] },
          {
            flow_id: ENV['MSG91_FLOW_ID'],
            sender: ENV['MSG91_SENDER_ID'],
            to: params[:customer_number],
            otp: '2135',
            store: @shop.owner_name
          }
        )
      else
        resp = TwilioServices::SendOtpService.new({
          from: ENV["TWILIO_PHONE_NUMBER"],
          to: params[:customer_number],
          body: get_sms_body,
          country_code: @shop.country_code,
        }).call
      end
      @shop.increment!(:test_notif_count) unless resp.sid.blank?
      puts "twilio resp = #{resp}"
    else
      SlackNotifyJob.perform_async(
        ":rage: Send Test SMS (#{Rails.env})\n *Error* reached max test tries #{@shop.shopify_domain}"
      )
      resp = OpenStruct.new({
                              sid: nil,
                              error: I18n.t("admin.free_limit_exhausted"),
                            })
    end
    resp
  end

  def get_sms_body
    body = params[:template]
    if body.include? "{{link}}"
      token = ENV["BITLY_TOKEN"].split(",")[0] # Picks always first Bitly token as this is not heavily called...
      client = Bitly::API::Client.new(token: token)
      bitlink = client.shorten(long_url: "https://apps.shopify.com/cash-on-delivery-cod-order-confirmation")
      body = body.gsub("{{link}}", bitlink.link)
    end
    otp_length = 6
    otp = rand(otp_length ** otp_length).to_s.rjust(otp_length, "0")
    body.gsub("{{otp}}", otp)
        .gsub("{{name}}", @shop.shop_owner.partition(" ").first)
        .gsub("{{amount}}", "100")
  end
end
