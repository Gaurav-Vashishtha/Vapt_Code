module NetworkServices
    class GupshupWhatsappPrepaidService < ApplicationService
      attr_reader :shop, :order_confirmation

      #NetworkServices::GupshupWhatsappPrepaidService.call(shop, order_confirmation)

  
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
  
        request = Net::HTTP::Post.new(uri)
        request['Cache-Control'] = 'no-cache'
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request['apikey'] = ENV.fetch("GUPSHUP_API_KEY", nil)

        discount = @shop.setting.prepaid_discount 
        if @shop.setting.prepaid_discount_type == 'FLAT'
          discount =  "#{discount} EGP OFF"
        else
          discount = "#{discount} % OFF"
        end


        payment_link = "https://#{ENV.fetch("APP_HOST", nil)}/order_confirmations/redirect_payment_link?domain=#{@shop.shopify_domain}&id=#{@order_confirmation.id}"
        payment_link = NetworkServices::CutlyLinkService.call(payment_link) 
        
        payment_link= payment_link.gsub('https://rzp.io/','').gsub('https://cutt.ly/','')
  
        template_payload = {
          id: ENV.fetch("GUPSHUP_TEMPLATE_ID", nil) || 'b00d7587-cb17-4b39-9969-68c0331543a0',
          params: [
            order_confirmation.order_number || "{{1}}",
            order_confirmation.order_amount || "{{2}}",
            discount || "{{3}}",
            payment_link
          ]
        }
  
        request.set_form_data(
          'channel' => 'whatsapp',
          'source' => ENV.fetch("GUPSHUP_SOURCE", nil) || '201501635356',
          'destination' => order_confirmation.customer_number,
          'src.name' => ENV.fetch("GUPSHUP_SRC_NAME", nil) || 'Hatchill123',
          'template' => template_payload.to_json
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
  