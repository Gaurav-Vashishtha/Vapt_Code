module SmsServices
  class BrandedSmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key.split(':')
      @sender_id = sender_id
      @params = params
    end

    def call
      url = "https://secure.h3techs.com/sms/api/send?email=#{@api_key.first}&key=#{@api_key.last}&mask=#{@sender_id}&to=#{@params[:to].gsub('+', '')}&message=#{@params[:body]}"
      begin
        uri = URI.parse(url)
      rescue URI::InvalidURIError
        uri = URI.parse(URI.escape(url))
      end
      begin
        resp = HTTParty.get(uri, format: :json)
        puts "brandedsms response #{resp}"
        puts "brandedsms parsed_response #{resp.parsed_response}"
        if resp.parsed_response['sms'] && resp.parsed_response['sms']['id']
          return OpenStruct.new({
            sid: 'brandedsms:' + resp.parsed_response['sms']['id']
          })
        end
        return OpenStruct.new({
          sid: nil,
          error: "Branded SMS: #{resp.parsed_response['sms']['response']}"
        })
      rescue Exception => e
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Error* Branded SMS service \n resp: #{resp.parsed_response} \n params: #{params} \n exception: #{e.message}"
        )
        return OpenStruct.new({
          sid: nil,
          error: 'Branded SMS: Server Down'
        })
      end
    end
  end
end