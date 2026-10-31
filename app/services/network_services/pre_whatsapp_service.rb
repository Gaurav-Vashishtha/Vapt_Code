require "httparty"

module NetworkServices
  class PreWhatsappService < ApplicationService
    attr_reader :shop, :customer_number, :otp

    # Example call:
    # resp = NetworkServices::PreWhatsappService.call(Shop.first, '919130751989', '1234')

    def initialize(shop, customer_number, otp)
      @shop = shop
      @customer_number = customer_number
      @otp = otp
    end

    def call
      return if @customer_number.blank?

      headers = {
        'Content-Type' => 'application/json',
        'authkey' => shop.setting.whatsapp_operator_config.presence || ENV.fetch("MSG91_AUTHKEY", nil),
      }

      whatsapp_number = @shop.setting.branded_whatsapp_number.presence || ENV.fetch("WHATSAPP_NUMBER_DEFAULT", nil)
      template_name = @shop.setting.whatsapp_pre_verify_otp_template.presence ||
                      (whatsapp_number == ENV.fetch("WHATSAPP_NUMBER_DEFAULT", nil) ? 'pre_verify_otp1' : 'pre_verify_otp')
      
      template_namespace = ENV.fetch("MSG91_TEMPLATE_NAMESPACE", nil) || '42f54ee8_898d_4edf_953e_7209c3f37deb'
      

      body = {
        integrated_number: whatsapp_number,
        content_type: 'template',
        payload: {
          messaging_product: 'whatsapp',
          type: 'template',
          template: {
            name: template_name,
            language: {
              code: ::Whatsapp::TemplateLanguage.for(@shop, template_name),
              policy: 'deterministic'
            },
            namespace: template_namespace,
            to_and_components: [
              {
                to: [@customer_number],
                components: {
                  body_1: {
                    type: 'text',
                    value: @otp
                  },
                  button_1: {
                    type: 'text',
                    subtype: 'url',
                    value: @otp
                  }
                }
              }
            ]
          }
        }
      }

      response = HTTParty.post(
        'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/',
        body: body.to_json,
        headers: headers
      )

      parse_response(response)
    end

    private

    def parse_response(response)
      JSON.parse(response.body) rescue { error: "Invalid JSON response", raw: response.body }
    end
  end
end
