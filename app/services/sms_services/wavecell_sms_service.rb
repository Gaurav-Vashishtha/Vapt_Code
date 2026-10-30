module SmsServices
  class WavecellSmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key.split(':')
      @sender_id = sender_id
      @params = params
    end

    def call
      url = "https://sms.8x8.com/api/v1/subaccounts/#{@api_key.first}/messages"
      begin
        resp = HTTParty.post(url,
          body: {
            source: @sender_id,
            destination: @params[:to],
            text: @params[:body],
            encoding: "AUTO"
          }.to_json,
          headers: {
            Authorization: "Bearer #{@api_key.last}",
            "Content-Type": "application/json"
          },
          format: :json,
          # debug_output: STDOUT
        )
        puts "WaveCell response #{resp}"
        puts "WaveCell parsed_response #{resp.parsed_response}"
        if resp.parsed_response['umid']
          return OpenStruct.new({
            sid: 'WaveCell:' + resp.parsed_response['umid']
          })
        end
        err_msg =  resp.parsed_response['message'] || resp.parsed_response['title']
        return OpenStruct.new({
          sid: nil,
          error: "WaveCell: #{err_msg}"
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