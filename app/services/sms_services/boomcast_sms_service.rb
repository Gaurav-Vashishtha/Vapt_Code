module SmsServices
    class BoomcastSmsService < ApplicationService
      attr_reader :api_key
      attr_reader :sender_id
      attr_reader :params
  
      def initialize(api_key, sender_id, params)
        @api_key = api_key.split(':')
        @sender_id = sender_id
        @params = params
      end
  
      def call
        begin
          username = @api_key.first
          password = @api_key.last
          masking = @sender_id
          receiver = params[:to]
          message = URI.encode_www_form_component(params[:body])
  
          uri = URI.parse("http://api.boom-cast.com/boomcast/WebFramework/boomCastWebService/externalApiSendTextMessage.php?" \
            "masking=#{masking}&userName=#{username}&password=#{password}&MsgType=TEXT&receiver=#{receiver}&message=#{message}")
  
          response = Net::HTTP.get_response(uri)
          parsed_response = response.body
          puts "Boomcast response: #{parsed_response}"
  
          if response.is_a?(Net::HTTPSuccess) && !parsed_response.blank?
            return OpenStruct.new({
              sid: "boomcast:#{receiver}:#{Time.now.to_i}", # Generating a unique SID using timestamp
              response: parsed_response
            })
          else
            return OpenStruct.new({
              sid: nil,
              error: parsed_response
            })
          end
        rescue => e
          return OpenStruct.new({
            sid: nil,
            error: e.message
          })
        end
      end
    end
  end
  