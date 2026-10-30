# Enhanced Service Class with language_code support
module NetworkServices
  class DynamicAbandonedCartWhatsappService < ApplicationService
    attr_reader :shop, :db_abandon_cart

    def initialize(shop, db_abandon_cart)
      @shop = shop
      @db_abandon_cart = db_abandon_cart
    end

    def call
      return if shop.setting.locked || db_abandon_cart.blank?

      dynamic_config = parse_dynamic_config
      template_name = dynamic_config['templateName'] || 'ac_fallback'
      variable_keys = dynamic_config['variables'].to_s.split(',').map(&:strip).reject(&:blank?)

      # ✅ Decide if featured_image is requested
      wants_featured_image = variable_keys.include?('featured_image')

      # ✅ Body variables exclude featured_image
      body_variable_keys = variable_keys - ['featured_image']

      # ✅ Generate discount code if needed
      discount_code = dynamic_config['discountCode']
      if discount_code == 'AUTO_GENERATE'
        generated_code = generate_discount_code(shop, dynamic_config)
        dynamic_config['discountCode'] = generated_code
        discount_code = generated_code
        db_abandon_cart.update(dynamic_config: dynamic_config)
      end

      # ✅ Build abandoned URL
      if db_abandon_cart.url.blank?
        return
      end
      abandoned_url = build_url_with_params(db_abandon_cart.url, discount_code)

      product_info = AbandonCartSchedule.find_by(cart_id: db_abandon_cart.checkout_id)&.product_info || 'Product'

      # ✅ Build components
      components = []

      # Header image component if featured_image was in variables and present
      if wants_featured_image && db_abandon_cart.featured_image.present?
        components << {
          type: "header",
          parameters: [
            {
              type: "image",
              image: {
                link: db_abandon_cart.featured_image
              }
            }
          ]
        }
      end

      # Body parameters - only add if there are valid variables
      if body_variable_keys.present?
        components << {
          type: "body",
          parameters: build_variable_payload(body_variable_keys, dynamic_config, product_info)
        }
      end

      # Button with short link
      components << {
        type: "button",
        index: "0",
        sub_type: "url",
        parameters: [
          {
            type: "text",
            text: NetworkServices::CutlyLinkService.call(abandoned_url).to_s.gsub("https://cutt.ly/", "")
          }
        ]
      }

      # ✅ Language code with fallback to 'en'
      language_code = dynamic_config['language_code'].presence || 'en'

      body = {
        integrated_number: shop.setting.branded_whatsapp_number.presence || ENV['WHATSAPP_NUMBER_DEFAULT'],
        content_type: "template",
        payload: {
          to: db_abandon_cart.phone,
          type: "template",
          messaging_product: "whatsapp",
          template: {
            name: template_name,
            language: {
              code: language_code,
              policy: "deterministic"
            },
            components: components
          }
        }
      }

      headers = {
        'Content-Type' => 'application/json',
        'authkey' => shop.setting.whatsapp_operator_config.presence || ENV['MSG91_AUTHKEY']
      }
      # Log the request for debugging
      Rails.logger.info "WhatsApp Template Request: #{body.to_json}"

      response = HTTParty.post(
        'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/',
        body: body.to_json,
        headers: headers
      )

      handle_response(response, body)
    end

    private

    def parse_dynamic_config
      config = db_abandon_cart.dynamic_config
      config.is_a?(Array) ? config.first || {} : config || {}
    end

    def build_variable_payload(variable_keys, config, product_info)
      variable_keys.map do |var|
        value = case var
                when 'name'
                  db_abandon_cart.name || 'Customer'
                when 'store'
                  shop.owner_name || shop.shopify_domain
                when 'product_info'
                  product_info
                when 'price'
                  db_abandon_cart.total_price.to_f.to_i.to_s
                when 'discount_code'
                  config['discountCode'].to_s
                when 'discount_value'
                  v = config['discountValue'].to_s
                  v += '%' if config['discountType'].to_s.casecmp('PERCENT').zero?
                  v
                when 'upto'
                  config['upto'].to_s
                else
                  'N/A'
                end

        value = 'N/A' if value.blank?
        { type: 'text', text: value }
      end
    end

    def handle_response(response, body = nil)
      response_hash = response.to_h

      if response_hash.present?
        db_abandon_cart.update(
          sid: response_hash.dig('data', 'message_uuid'),
          status: (response_hash['status'] == 'success') ? 'SUCCESS' : response_hash.to_s
        )
        # Kept briefly so a 131049 "healthy ecosystem" refusal can be retried.
        if body && db_abandon_cart.status == 'SUCCESS'
          Whatsapp::Msg91SendCapture.remember(shop: shop, source: db_abandon_cart, provider_id: db_abandon_cart.sid, url: 'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/', body: body)
        end
      end

      response
    end

    def build_url_with_params(base_url, discount_code)
      uri = URI(base_url)
      query = URI.decode_www_form(uri.query || '')

      query << ['discount', discount_code] if discount_code.present? && query.none? { |k, _| k == 'discount' }
      query << ['storefront', 'true'] if query.none? { |k, _| k == 'storefront' }

      uri.query = URI.encode_www_form(query)
      uri.to_s
    end

    def generate_discount_code(shop, config)
      discount_type = config['discountType']
      discount_value = config['discountValue'].to_f
      upto_amount = config['upto'].to_f
      cart_total = db_abandon_cart.total_price.to_f
      generated_code = "AC#{SecureRandom.hex(3).upcase}"

      shop.with_shopify_session do
        price_rule_params = {
          title: generated_code,
          target_type: "line_item",
          target_selection: "all",
          allocation_method: "across",
          customer_selection: "all",
          starts_at: Time.now.utc.iso8601,
          ends_at: 24.hours.from_now.utc.iso8601,
          usage_limit: 1,
          once_per_customer: true
        }

        if discount_type == 'FIXED'
          price_rule_params.merge!(
            value_type: 'fixed_amount',
            value: -discount_value
          )
        else
          calculated_discount = (cart_total * discount_value) / 100.0
          if upto_amount > 0 && calculated_discount > upto_amount
            price_rule_params.merge!(
              value_type: 'fixed_amount',
              value: -upto_amount
            )
          else
            price_rule_params.merge!(
              value_type: 'percentage',
              value: -discount_value
            )
          end
        end

        price_rule = ShopifyAPI::PriceRule.create(price_rule_params)

        ShopifyAPI::DiscountCode.create(
          price_rule_id: price_rule.id,
          code: generated_code
        )
      end

      generated_code
    rescue => e
      SlackNotifyJob.perform_async(":boom: Discount generation failed for #{shop.shopify_domain} – #{e.message}")
      "DISCOUNTFAIL"
    end
  end
end
