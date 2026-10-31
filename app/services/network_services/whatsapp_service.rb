require "httparty"

#NetworkServices::WhatsappService.call(Shop.last,OrderConfirmation.last)
module NetworkServices
  class WhatsappService < ApplicationService
    attr_reader :shop, :order_confirmation

    def initialize(shop, order_confirmation)
      @shop = shop
      @order_confirmation = order_confirmation
    end

    def call
      return if @shop.setting.locked

      return call_branded_service if branded_whatsapp_applicable?
      return call_gupshup_service if shop.shopify_domain == 'bonsai-eg.myshopify.com'
     #return if approval_rejected?
      return if blacklisted_number?

      return unless @order_confirmation.present?

      headers = {
        'Content-Type' => 'application/json',
        'authkey' => shop.setting.whatsapp_operator_config.presence || ENV.fetch("MSG91_AUTHKEY", nil)
      }

      payload = build_payload
      response = HTTParty.post(
        'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/',
        body: payload.to_json,
        headers: headers
      )

      log_response(response, payload)
      response
    end

    private

    def branded_whatsapp_applicable?
      @shop.setting.whatsapp_operator_config.present?
    end

    def call_branded_service
      templates = BrandedWhatsappTemplate.where(shop_id: @shop.id, template_type: 'OTP')
      if templates.any?
        NetworkServices::BrandedWhatsappService.call(@shop, @order_confirmation, nil, templates.first, '')
      else
        SlackNotifier::CLIENT.ping("Error sending Branded whatsapp template for OTP - Template not configured - #{@shop.shopify_domain}")
        "Template not found for Abandoned cart OTP for Branded whatsapp config"
      end
    end

    def call_gupshup_service
      NetworkServices::GupshupWhatsappService.call(@shop, @order_confirmation)
    end

    def approval_rejected?
      @shop.setting.whatsapp_approval_status == 'rejected' ||
        (!Rails.env.development? && @shop.id > 38500 && @shop.setting.whatsapp_approval_status != 'approved')
    end

    def blacklisted_number?
      ENV.fetch("BLACKLISTED_PHONE_NUMBERS", nil).to_s.split(',').include?(@order_confirmation.customer_number).tap do |blacklisted|
        if blacklisted
          SlackNotifyJob.perform_async(":rage:  (#{Rails.env})\n Blacklisted number found - Whatsapp - order ID #{@order_confirmation.order_id} shop #{@shop.shopify_domain}")
        end
      end
    end

    def otp_template_name
      @shop.setting.whatsapp_pre_verify_otp_template.presence || ENV.fetch("MSG91_TEMPLATE_NAME", nil) || 'pre_verify_otp'
    end

    def build_payload
      {
        integrated_number: @shop.setting.branded_whatsapp_number.presence || ENV.fetch("WHATSAPP_NUMBER_DEFAULT", nil),
        content_type: 'template',
        payload: {
          messaging_product: 'whatsapp',
          type: 'template',
          template: {
            name: otp_template_name,
            language: {
              code: ::Whatsapp::TemplateLanguage.for(@shop, otp_template_name),
              policy: 'deterministic'
            },
            namespace: ENV.fetch("MSG91_TEMPLATE_NAMESPACE", nil) || '42f54ee8_898d_4edf_953e_7209c3f37deb',
            to_and_components: [
              {
                to: [@order_confirmation.customer_number],
                components: {
                  body_1: {
                    type: 'text',
                    value: @order_confirmation.persisted_otp.to_s
                  },
                  button_1: {
                    type: 'text',
                    subtype: 'url',
                    value: @order_confirmation.persisted_otp.to_s
                  }
                }
              }
            ]
          }
        }
      }
    end

    def generate_tracking_url
      "#{ENV.fetch("OTP_TRACKING_BASE_URL", nil)}/track/#{@order_confirmation.order_id}"
    end

    def log_response(response, payload = nil)
      resp_hash = JSON.parse(response.body) rescue {}
    
      return if resp_hash.blank?
    
      log = TwilioLog.create(
        sid: resp_hash.dig('request_id'),
        ver_type: 'WHATSAPP',
        country_code: @order_confirmation.country_code,
        customer_number: @order_confirmation.customer_number,
        status: resp_hash['status'] == 'success' ? 'SUCCESS' : resp_hash.to_s,
        order_confirmation: @order_confirmation,
        shop: @shop
      )
      # Kept briefly so a 131049 "healthy ecosystem" refusal can be retried.
      if payload && log.persisted? && log.status == 'SUCCESS'
        Whatsapp::Msg91SendCapture.remember(
          shop: @shop, source: log, provider_id: log.sid,
          url: 'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/', body: payload
        )
      end
    end
  end
end
