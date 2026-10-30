module SmsServices
  class WinsmsproSmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key
      @sender_id = sender_id
      @params = params
    end

    def call
      # Properly encode the message body to handle special characters
      encoded_body = URI.encode_www_form_component(@params[:body].to_s)
      url = "https://www.winsmspro.com/sms/sms/api?action=send-sms&api_key=#{@api_key.gsub(' ', '')}&to=#{@params[:to].gsub('+', '').gsub(' ', '')}&from=#{@sender_id}&sms=#{encoded_body}"
      begin
        uri = URI.parse(url)
      rescue URI::InvalidURIError
        # Fallback: encode the entire URL if parsing still fails (shouldn't happen with proper encoding)
        require 'cgi'
        uri = URI.parse(CGI.escape(url))
      end
      begin
        resp = HTTParty.get(uri)
        puts "winsms response #{resp}"
        puts "winsms parsed_response #{resp.parsed_response}"
        if resp.parsed_response['code'] === 'ok'
          return OpenStruct.new({
            sid: 'winsmspro:' + (resp.parsed_response['balance'] + 1).to_s
          })
        end
        return OpenStruct.new({
          sid: nil,
          error: "WinSMS: #{resp.parsed_response['message']}"
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