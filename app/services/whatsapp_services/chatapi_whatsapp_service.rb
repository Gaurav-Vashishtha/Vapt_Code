module WhatsappServices
  class ChatapiWhatsappService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key
      @sender_id = sender_id
      @params = params
    end

    def call
      url = "https://api.chat-api.com/instance#{@sender_id}/sendMessage?token=#{@api_key}"
      begin
        resp = HTTParty.post(url,
          body: {
            phone: @params[:to],
            body: @params[:body]
          },
          headers: {
            'accept' => 'application/json',
            'Content-Type' => 'application/x-www-form-urlencoded'
          }
        )
        puts "chatapi response #{resp}"
        puts "chatapi parsed_response #{resp.parsed_response}"
        if resp.success?
          return OpenStruct.new({
            sid: 'chatapi:' + resp.parsed_response['id']
          })
        end
        return OpenStruct.new({
          sid: nil,
          error: "chatapi: Error"
        })
      rescue Exception => e
        return OpenStruct.new({
          sid: nil,
          error: e.message
        })
      end
    end

  end
end