module SmsServices
  class PalPigeonSmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key.split(':')
      @sender_id = sender_id
      @params = params
    end

    def call
      url = "http://www.postaguvercini.com/api_http/sendsms.asp?user=#{@api_key.first}&password=#{@api_key.last}&gsm=#{@params[:to].gsub('+', '').delete_prefix('0').delete('^0-9')}&text=#{@params[:body]}"
      begin
        uri = URI.parse(url)
      rescue URI::InvalidURIError
        uri = URI.parse(URI.escape(url))
      end
      begin
        resp = HTTParty.get(uri)
        puts "PalPegeon response #{resp}"
        puts "PalPegeon parsed_response #{resp.parsed_response}"
        if resp.ok?
          parsed_response = Rack::Utils.parse_nested_query resp.parsed_response
        end
        if !parsed_response['message_id'].blank?
          return OpenStruct.new({
            sid: 'PalPegeon:' + parsed_response['message_id']
          })
        end
        return OpenStruct.new({
          sid: nil,
          error: "PalPigeon: #{parsed_response['errtext'].encode("UTF-8", "Windows-1252") || parsed_response['errno'].encode("UTF-8")}"
        })
      rescue Exception => e
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Error* PalPigeon SMS service \n resp: #{resp.parsed_response.encode("UTF-8", "Windows-1252")} \n params: #{params} \n exception: #{e.message}"
        )
        return OpenStruct.new({
          sid: nil,
          error: 'PalPigeon: Server Down'
        })
      end
    end
  end
end