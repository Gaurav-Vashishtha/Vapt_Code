module SmsServices
  class SmsshareSmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key
      @params = params
      @sender_id = sender_id
      @gti = params[:dlt_id]
    end

    def call
      url = "https://smshare.fr/api/v2/sms/bulk"
      begin
        resp = HTTParty.post(url,
          body: {
            accessToken: @api_key,
            gateway: @sender_id,
            smsBeans: [{
              destination: @params[:to],
              message: @params[:body],
              gti: @gti
            }]
          }.to_json,
          headers: {
            'Content-Type' => 'application/json'
          }
        )
        puts "smsshare response #{resp}"
        puts "smsshare parsed_response #{resp.parsed_response}"
        if resp.success?
          return OpenStruct.new({
            sid: 'smsshare:' + DateTime.now.to_i.to_s
          })
        end
        return OpenStruct.new({
          sid: nil,
          error: "smsshare: Error"
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