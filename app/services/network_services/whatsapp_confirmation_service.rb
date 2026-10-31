require "razorpay"
module NetworkServices
  class WhatsappConfirmationService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation

    #resp = NetworkServices::WhatsappConfirmationService.call(Shop.last,OrderConfirmation.last)

    def initialize(shop, order_confirmation, is_partial_payment_order=false)
      @shop = shop
      @order_confirmation = order_confirmation
      @is_partial_payment_order = is_partial_payment_order
    end


    # Never raises, and never re-reads after a failure: a revoked token (401),
    # a deleted order (404) or Shopify throttling resolves to nil once and the
    # confirmation goes out with the stored OrderConfirmation values plus
    # Notifications::Defaults, instead of being dropped.
    def get_shopify_order(order_confirmation)
      return @shopify_order_memo if defined?(@shopify_order_memo)

      @shopify_order_memo = ShopifyServices::SafeOrderReader.find(order_confirmation.shop, order_confirmation.order_id)
    end

    def fetch_and_save_order_status_url(order_confirmation,shopify_order)
      if !shopify_order.blank?
        order_confirmation.update(order_status_url:shopify_order.order_status_url)
      end
      return order_confirmation
    end

    def partial_order_created?(shopify_order)
      return false if shopify_order.blank?
      return false unless shopify_order.note.is_a?(String)
    
      shopify_order.note.downcase.include?("partial order created".downcase)
    end
    

    def call
      if @shop.setting.locked 
        return
      end
      # if !@shop.setting.whatsapp_operator_config.blank?
      #   branded_templates = BrandedWhatsappTemplate.where(shop_id:@shop.id,template_type:'Order_Confirmation')
      #   if branded_templates.size>0
      #     return  NetworkServices::BrandedWhatsappService.call(@shop, @order_confirmation ,nil,branded_templates.first,'')
      #   else
      #     SlackNotifier::CLIENT.ping(
      #         text: "Error sending Branded whatsapp template for Order_Confirmation - Template not configured - #{@shop.shopify_domain}",
      #       )
      #     return "Template not found for Order_Confirmation for Branded whatsapp config"
      #   end
      # end

      # Test sends (sentinel order id) always go through, regardless of approval —
      # the approval status only gates live customer delivery.
      is_test_order = @order_confirmation.order_id == '1234567890'
      if !is_test_order && (@shop.setting.whatsapp_approval_status=='rejected' || (!Rails.env.development? && @shop.id > 38500 && @shop.setting.whatsapp_approval_status !='approved'))
        return
      end

      if  ENV.fetch("BLACKLISTED_PHONE_NUMBERS", nil).split(',').include?@order_confirmation.customer_number
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n Blacklisted number found - Whatsapp - order ID #{@order_confirmation.order_id} shop #{@order_confirmation.shop.shopify_domain}"
        )
        return
      end

      if @order_confirmation.twilio_logs.where(ver_type:'WHATSAPP-CONFIRMATION').count > 0 && @order_confirmation.order_id !='1234567890'
        return
      end
      shopify_order = ''
      if @order_confirmation.order_id !='1234567890'
        # Shopify order is fetched lazily only if needed (missing configured vars or missing status url)
        shopify_order = nil
      end
      
      # Template config supports optional variable list:
      #   template_name:customer_name$order_id$order_amount$product_name$variant_name$image_url$shipping_address
      # Body param order follows the configured list. Button is always status url.
      template_config = @shop.setting.whatsapp_order_confirmation_template.presence || "order_confirmation"
      template, requested_vars = parse_template_config(template_config)
      language_code = ::Whatsapp::TemplateLanguage.for(@shop, template)
      # If template asks for product/variant/image/shipping_address, we must fetch Shopify order
      # to get line_items / product_id / shipping_address.
      if @order_confirmation.order_id != '1234567890' &&
         requested_vars.any? { |v| %w[product_name variant_name image_url shipping_address].include?(v) }
        shopify_order = get_shopify_order(order_confirmation)
      end
      
      # Determine language code based on template if not explicitly set
      if template.include?('_it') && language_code == 'en'
        language_code = 'it'
      end

      # if partial_order_created?(shopify_order)
      #   # Override the template here...
      # end

      # Ensure status URL exists (needed for button). Fetch Shopify order if status URL is missing.
      if @order_confirmation.order_id !='1234567890' && @order_confirmation.order_status_url.blank?
        shopify_order = get_shopify_order(order_confirmation)
        @order_confirmation = fetch_and_save_order_status_url(@order_confirmation, shopify_order)
      end

      cutly_url = NetworkServices::CutlyLinkService.call(@order_confirmation.order_status_url)
      cutly_url = @order_confirmation.order_status_url if cutly_url.blank?

      # Compute values for configured vars. If any are missing, fetch Shopify order and retry.
      values = build_configured_values(requested_vars, shopify_order)
      if @order_confirmation.order_id !='1234567890' && values.values.any?(&:blank?)
        shopify_order = get_shopify_order(order_confirmation)
        values = build_configured_values(requested_vars, shopify_order)
      end
      
      currency_symbol = CurrencyHelper.symbol_for(@order_confirmation.currency) || @order_confirmation.currency


      if @is_partial_payment_order && shopify_order.present? && values["order_amount"].present?
        # If order_amount is requested, override it for partial-payment orders using Shopify totals.
        if @shop.setting.partial_payment_flow=='SAME_ORDER'
          values["order_amount"] = "Total : #{currency_symbol} #{shopify_order.current_total_price} - Balance remaining: #{currency_symbol} #{shopify_order.total_outstanding}" 
        else
          total = shopify_order.current_total_price.to_f+shopify_order.current_total_discounts.to_f
          balance = total - (shopify_order.current_total_discounts.to_f)
          values["order_amount"] = "Total : #{currency_symbol} #{total} - Balance remaining: #{currency_symbol} #{balance}" 
        end
      end

      if !@order_confirmation.blank? 
        integrated_whatsapp_number = @shop.setting.branded_whatsapp_number 
        if integrated_whatsapp_number.blank?
          integrated_whatsapp_number = ENV.fetch("WHATSAPP_NUMBER_DEFAULT", nil)
        end
        
        headers = {
          'Content-Type' => 'application/json',
          'authkey' => shop.setting.whatsapp_operator_config.presence || ENV.fetch("MSG91_AUTHKEY", nil),
        }
        body = {
          "integrated_number": integrated_whatsapp_number,
          "content_type": "template",
          "payload": {
            "to": @order_confirmation.customer_number,
            "type": "template",
            "template": {
              "name": template,
              "language": {
                "code": language_code,
                "policy": "deterministic"
              },
              "components": build_components_from_config(requested_vars, values, cutly_url)
            },
            "messaging_product": "whatsapp"
          }
        }
        
        resp = HTTParty.post('https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/',
                                  body: body.to_json,
                                  headers: headers)
        resp_hash = resp.to_h
        if !resp_hash.blank?
          TwilioLog.create(
            sid: resp_hash.dig('data','message_uuid'),
            ver_type: 'WHATSAPP-CONFIRMATION',
            country_code: @order_confirmation.country_code,
            customer_number: @order_confirmation.customer_number,
            status: (resp_hash['status']=='success') ? 'SUCCESS' : resp_hash.to_s,
            order_confirmation_id: @order_confirmation.id,
            shop_id: @shop.id,
          )
        end
        resp
      end
    end

    SUPPORTED_TEMPLATE_VARS = %w[
      customer_name
      store
      order_id
      order_amount
      product_name
      variant_name
      image_url
      shipping_address
    ].freeze

    def parse_template_config(raw)
      s = raw.to_s.strip
      return ["order_confirmation", ["customer_name", "store", "order_id", "order_amount"]] if s.blank?

      name, rest = s.split(":", 2)
      template_name = name.to_s.strip.presence || "order_confirmation"
      vars = rest.to_s.split("$").map { |v| v.to_s.strip }.reject(&:blank?)
      vars = vars.select { |v| SUPPORTED_TEMPLATE_VARS.include?(v) }
      vars = ["customer_name", "store", "order_id", "order_amount"] if vars.empty?
      [template_name, vars]
    end

    def build_components_from_config(vars, values, cutly_url)
      components = []

      if vars.include?("image_url") && values["image_url"].present?
        components << {
          "type": "header",
          "parameters": [
            {
              "type": "image",
              "image": {
                "link": values["image_url"]
              }
            }
          ]
        }
      end

      body_vars = vars.reject { |v| v == "image_url" }
      components << {
        "type": "body",
        "parameters": body_vars.map do |v|
          {
            "type": "text",
            # Meta rejects the whole send when any body parameter is empty, so a
            # value we couldn't resolve (Shopify unreadable and nothing stored
            # locally) goes out as a neutral placeholder instead.
            "text": Notifications::Defaults.value(values[v])
          }
        end
      }

      components << {
        "type": "button",
        "index": "0",
        "sub_type": "url",
        "parameters": [
          {
            "type": "text",
            "text": begin
              u = cutly_url.to_s
              u.start_with?("https://cutt.ly/") ? u.delete_prefix("https://cutt.ly/") : u
            end
          }
        ]
      }

      components
    end

    def build_configured_values(vars, shopify_order)
      out = {}
      vars.each do |v|
        out[v] = resolve_var_value(v, shopify_order)
      end
      out
    end

    def resolve_var_value(var, shopify_order)
      case var
      when "customer_name"
        Notifications::Defaults.name(@order_confirmation.customer_name)
      when "store"
        @shop.owner_name.presence || @shop.shopify_domain.to_s
      when "order_id"
        Notifications::Defaults.value(
          @order_confirmation.customer_facing_order_number.to_s.presence ||
            shopify_order&.order_number.to_s.presence ||
            @order_confirmation.order_id.to_s
        )
      when "order_amount"
        if @order_confirmation.order_amount.present?
          (@order_confirmation.order_amount.to_f + (@order_confirmation.cod_fee || 0)).to_s
        else
          shopify_order&.current_total_price.to_s
        end
      when "product_name"
        line_item_titles(shopify_order).presence
      when "variant_name"
        line_item_variant_titles(shopify_order).presence
      when "image_url"
        li = first_line_item(shopify_order)
        pid = li&.product_id
        fetch_product_image_url(pid)
      when "shipping_address"
        format_shipping_address(shopify_order)
      else
        nil
      end
    end

    # Builds a single-line, WhatsApp-safe shipping address from a Shopify order.
    # WhatsApp Cloud API rejects body parameters containing newlines, tabs, or 4+ consecutive spaces,
    # so the output is joined with ", " and whitespace-squeezed.
    def format_shipping_address(shopify_order)
      return nil if shopify_order.blank?
      addr =
        begin
          shopify_order.respond_to?(:shipping_address) ? shopify_order.shipping_address : nil
        rescue StandardError
          nil
        end
      return nil if addr.blank?

      read = ->(field) {
        addr.respond_to?(field) ? addr.public_send(field).to_s.strip.presence : nil
      }

      name = read.call(:name) || [read.call(:first_name), read.call(:last_name)].compact.join(" ").presence
      province_zip = [read.call(:province), read.call(:zip)].compact.join(" ").presence

      parts = [
        name,
        read.call(:address1),
        read.call(:address2),
        read.call(:city),
        province_zip,
        read.call(:country)
      ].compact.reject(&:blank?)

      return nil if parts.empty?

      parts.join(", ").gsub(/[\r\n\t]+/, ' ').gsub(/ {2,}/, ' ').strip
    end

    def fetch_product_image_url(product_id)
      return nil if product_id.blank?
      @product_image_cache ||= {}
      return @product_image_cache[product_id] if @product_image_cache.key?(product_id)

      url =
        begin
          # Ensure Shopify session is active for REST Product API call
          @shop.init_session if @shop.respond_to?(:init_session)
          product = ShopifyAPI::Product.find(product_id)
          img = product&.image
          # Some shops have `images` only
          img ||= Array(product&.images).first
          (img&.src || img&.url).to_s.presence
        rescue StandardError
          nil
        end

      @product_image_cache[product_id] = url
      url
    end

    def line_items(shopify_order)
      return [] if shopify_order.blank?
      items =
        begin
          shopify_order.respond_to?(:line_items) ? shopify_order.line_items : nil
        rescue StandardError
          nil
        end
      Array(items)
    end

    def line_item_titles(shopify_order)
      titles = line_items(shopify_order).map { |li| li&.title.to_s.strip }.reject(&:blank?)
      titles.join(", ")
    end

    def line_item_variant_titles(shopify_order)
      variants =
        line_items(shopify_order).map do |li|
          v = (li&.variant_title || li&.name).to_s.strip
          v.presence
        end.compact
      variants.join(", ")
    end

    def first_line_item(shopify_order)
      line_items(shopify_order).first
    end
  end
end