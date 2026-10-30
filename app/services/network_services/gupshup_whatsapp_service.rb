module NetworkServices
    class GupshupWhatsappService < ApplicationService
      attr_reader :shop, :order_confirmation
  
      def initialize(shop, order_confirmation)
        @shop = shop
        @order_confirmation = order_confirmation
      end
  
      def call
        return if shop.setting.locked
        send_otp_via_gupshup
      end
  
      private
  
      def send_otp_via_gupshup
        uri = URI.parse('https://api.gupshup.io/wa/api/v1/template/msg')
  
        request = Net::HTTP::Post.new(uri)
        request['Cache-Control'] = 'no-cache'
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request['apikey'] = ENV['GUPSHUP_API_KEY']
  
        request.set_form_data(
          'channel' => 'whatsapp',
          'source' => ENV['GUPSHUP_SOURCE'] || '201501635356',
          'destination' => order_confirmation.customer_number,
          'src.name' => ENV['GUPSHUP_SRC_NAME'] || 'Hatchill123',
          'template' => {
            id: ENV['GUPSHUP_TEMPLATE_ID'] || 'e65be9e8-f6f7-4ef5-8148-86ce5859bad0',
            params: [order_confirmation.persisted_otp]
          }.to_json
        )
  
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end
  
        parsed = JSON.parse(response.body) rescue {}
  
        TwilioLog.create(
          sid: parsed['messageId'],
          ver_type: 'WHATSAPP',
          country_code: order_confirmation.country_code,
          customer_number: order_confirmation.customer_number,
          status: parsed['status'] == 'submitted' ? 'SUCCESS' : parsed.to_s,
          order_confirmation: order_confirmation,
          shop: shop
        )
  
        parsed
      rescue => e
        TwilioLog.create(
          ver_type: 'WHATSAPP',
          country_code: order_confirmation.country_code,
          customer_number: order_confirmation.customer_number,
          status: "Error: #{e.message}",
          order_confirmation: order_confirmation,
          shop: shop
        )
        raise e
      end
    end
  end
  