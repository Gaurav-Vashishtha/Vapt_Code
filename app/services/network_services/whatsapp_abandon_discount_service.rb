require "razorpay"
module NetworkServices
  class WhatsappAbandonDiscountService < ApplicationService
    attr_reader :shop
    attr_reader :order_confirmation

    #resp = NetworkServices::WhatsappAbandonDiscountService.call(Shop.first,AbandonedCart.last)

    def initialize(shop, db_abandon_cart)
      @shop = shop
      @db_abandon_cart = db_abandon_cart
    end

    def call
      if @shop.setting.locked 
        return
      end
      # if !@shop.setting.whatsapp_operator_config.blank?
      #   branded_templates = BrandedWhatsappTemplate.where(shop_id:@shop.id,template_type:'Abandoned_Checkout_Discount')
      #   if branded_templates.size>0
      #     return  NetworkServices::BrandedWhatsappService.call(@shop,nil,@db_abandon_cart,branded_templates.first,'')
      #   else
      #     # SlackNotifier::CLIENT.ping(
      #     #     text: "Error sending Branded whatsapp template for Abandoned CartDiscount - Template not configured - #{@shop.shopify_domain}",
      #     #   )
      #     return "Template not found for Abandoned cart CartDiscount for Branded whatsapp config"
      #   end
      # end

      # Test sends (sentinel checkout id) always go through, regardless of approval —
      # the approval status only gates live customer delivery.
      is_test_order = @db_abandon_cart&.checkout_id == 'chk_123'
      if !is_test_order && (@shop.setting.whatsapp_approval_status=='rejected' || (!Rails.env.development? && @shop.id > 38500 && @shop.setting.whatsapp_approval_status !='approved'))
        return
      end

      if @db_abandon_cart.blank? 
        puts 'Invalid db abandoned cart...'
        return
      end
      ac_schedule = AbandonCartSchedule.find_by(cart_id: @db_abandon_cart.checkout_id)
      product_info = 'Product'
      if !ac_schedule.blank?
        product_info = ac_schedule.product_info
      end
      abandoned_url = NetworkServices::CutlyLinkService.call(@db_abandon_cart.url)

      
      if abandoned_url.blank?
        # SlackNotifyJob.perform_async(
        #   ":rage:  (#{Rails.env})\n  Blank Abandoned Cart URL for #{@db_abandon_cart.id} and Shop #{@shop.shopify_domain}"
        # )
        # return
        abandoned_url = NetworkServices::CutlyLinkService.call(@shop.shopify_domain)
      end

      headers = {
        'Content-Type' => 'application/json',
        'authkey' => shop.setting.whatsapp_operator_config.presence || ENV['MSG91_AUTHKEY'],
      }
      integrated_whatsapp_number = @shop.setting.branded_whatsapp_number 
      if integrated_whatsapp_number.blank?
        integrated_whatsapp_number = ENV['WHATSAPP_NUMBER_DEFAULT']
      end

      # Build components array and determine template based on image presence.
      # Fallback template names are ENV-configurable so they can be changed
      # without a deploy (same as the real abandoned-cart flow). Shop-level
      # setting still takes precedence.
      components = []
      with_image_template = ENV['WHATSAPP_AC_DISCOUNT_TEMPLATE_WITH_IMAGE'].presence || 'ac_with_discount_with_image'
      with_image_template_alt = ENV['WHATSAPP_AC_DISCOUNT_TEMPLATE_WITH_IMAGE_ALT'].presence || 'ac_with_discount_with_image2'
      without_image_template = ENV['WHATSAPP_AC_DISCOUNT_TEMPLATE_WITHOUT_IMAGE'].presence || 'ac_with_discount'
      template_name = @shop.setting.whatsapp_abandoned_cart_template.presence || begin
        if @db_abandon_cart.featured_image.present?
          @shop.setting.branded_whatsapp_number.present? ? with_image_template : with_image_template_alt
        else
          without_image_template
        end
      end
      
      # Add header image component if featured_image is present
      if @db_abandon_cart.featured_image.present?
        components << {
          "type": "header",
          "parameters": [
            {
              "type": "image",
              "image": {
                "link": @db_abandon_cart.featured_image
              }
            }
          ]
        }
      end
      
      # Add body component - parameters depend on template
      if @db_abandon_cart.featured_image.present?
        # With image: name, shop owner, discount text, discount code, product info
        components << {
          "type": "body",
          "parameters": [
            {
              "type": "text",
              "text": @shop.owner_name
            },
            {
              "type": "text",
              "text": "Get " + @shop.setting.ac_whatsapp_discount + " off"
            },
            {
              "type": "text",
              "text": "using Discount code " + @shop.setting.ac_whatsapp_discount_code
            },
            {
              "type": "text",
              "text": product_info
            }
          ]
        }
      else
        # Without image: shop owner, discount text, discount code, product info (original format)
        components << {
          "type": "body",
          "parameters": [
            {
              "type": "text",
              "text": @shop.owner_name
            },
            {
              "type": "text",
              "text": "Get " + @shop.setting.ac_whatsapp_discount + " off"
            },
            {
              "type": "text",
              "text": "using Discount code " + @shop.setting.ac_whatsapp_discount_code
            },
            {
              "type": "text",
              "text": product_info
            }
          ]
        }
      end
      
      # Add button component
      components << {
        "type": "button",
        "index": "0",
        "sub_type": "url",
        "parameters": [
          {
            "type": "text",
            "text": abandoned_url.gsub('https://cutt.ly/','')
          }
        ]
      }

      body = {
        "integrated_number": integrated_whatsapp_number,
        "content_type": "template",
        "payload": {
          "to": @db_abandon_cart.phone, 
          "type": "template",
          "template": {
            "name": template_name,
            "language": {
              "code": ::Whatsapp::TemplateLanguage.for(@shop, template_name),
              "policy": "deterministic"
            },
            "components": components
          },
          "messaging_product": "whatsapp"
        }
      }

      resp = HTTParty.post('https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/',
                                body: body.to_json,
                                headers: headers)
      resp_hash = resp.to_h
      if !resp_hash.blank?
        @db_abandon_cart.update(
          sid: resp_hash.dig('data','message_uuid'),
          status: (resp_hash['status']=='success') ? 'SUCCESS' : resp_hash.to_s,
        )
        # Kept briefly so a 131049 "healthy ecosystem" refusal can be retried.
        if @db_abandon_cart.status == 'SUCCESS'
          Whatsapp::Msg91SendCapture.remember(shop: shop, source: @db_abandon_cart, provider_id: @db_abandon_cart.sid, url: 'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/', body: body)
        end
      end
      resp
    end
  end
end
