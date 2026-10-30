module NetworkServices
    class GupshupWhatsappRetryService < ApplicationService
      attr_reader :shop, :order_confirmation
  
      def initialize(shop, order_confirmation)
        @shop = shop
        @order_confirmation = order_confirmation
      end
  
      def call
        return if shop.setting.locked
        send_whatsapp_template
      end
  
      private
  
      def send_whatsapp_template
        uri = URI.parse('https://api.gupshup.io/wa/api/v1/template/msg')
        confirmation_url = NetworkServices::CutlyLinkService.call("https://#{ENV["APP_HOST"]}/order/verify?order_id=#{@order_confirmation.order_id}&code=#{@order_confirmation.persisted_otp}&id=#{@order_confirmation.shop.id}")
      
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
            id: ENV['GUPSHUP_TEMPLATE_ID'] || 'f1e4e2b8-7d1b-416c-b3ac-7cd62e620613',
            params: [confirmation_url.gsub('https://cutt.ly/', '')] # Fixed: wrap in array
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
  