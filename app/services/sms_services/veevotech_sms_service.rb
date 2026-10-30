require 'net/http'
require 'uri'


module SmsServices

  # resp = SmsServices::VeevotechSmsService.call(
  #             ENV['VEEVOTECH_API_KEY'],
  #             ENV['VEEVOTECH_SENDER_ID'],
  #           {
  #             to: '+923135096432',
  #             body: 'Hello from COD King'
  #           }
  #           )

  class VeevotechSmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key
      @sender_id = sender_id
      @params = params
    end
    
    def call
      begin
        #uri = URI.parse("https://api.veevotech.com/v3/sendsms?hash=82c9b11610b47d000d7900643de81f6e&receivernum=%2B923098222133&sendernum=8583&textmessage=HelloSMS%20from%20COD%20King")

        header_id = 'Online%20Purchase'
        if !@params[:header_id].blank?
          header_id = @params[:header_id]
        end

        uri =URI.parse("https://api.veevotech.com/v3/sendsms?hash=#{@api_key.gsub(' ', '')}&header=#{header_id}&receivernum=#{@params[:to]}&sendernum=#{@sender_id}&textmessage=#{@params[:body]}")
        response = Net::HTTP.get_response(uri)
        parsed_response = JSON.parse(response.body).to_h
        sid = parsed_response['MESSAGE_ID']
        return OpenStruct.new({
          sid: "veevotech #{sid}",
          error: parsed_response['ERROR_DESCRIPTION']
        })
      rescue Exception => e
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Error* Veevotech SMS service \n resp: #{response.body} \n params: #{params} \n exception: #{e.message}"
        )
        return OpenStruct.new({
          sid: nil,
          error: 'Veevotech: Server Down'
        })
      end
    end
  end
end