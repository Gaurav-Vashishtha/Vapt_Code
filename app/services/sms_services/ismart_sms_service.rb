module SmsServices
  class IsmartSmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key
      @sender_id = sender_id
      @params = params
    end

    def call
      url = "https://ismartsms.net/RestApi/api/SMS/PostSMS"
      begin
        uri = URI.parse(url)
      rescue URI::InvalidURIError
        uri = URI.parse(URI.escape(url))
      end
      begin
        resp = HTTParty.post(uri,
          body: URI.encode_www_form({
            UserID: @sender_id,
            Password: @api_key,
            Message: @params[:body],
            # 0 for English and 64 for Arabic.
            Language: '0',
            # "ScheddateTime": "01/22/2017 00:00:00",
            MobileNo: [@params[:to].gsub('+', '').gsub(' ', '')],
            # 1 for Normal SMS and 9 for Flash SMS
            RecipientType: '1',
            ScheddateTime: '01/22/2017 00:00:00'
          }),
          headers: {
            'Content-Type' => 'application/x-www-form-urlencoded'
          }
        )
        puts "ismartsms response #{resp}"
        puts "ismartsms parsed_response #{resp.parsed_response}"
        if resp.parsed_response['Code'] == 1
          return OpenStruct.new({
            sid: 'iSmart:' + DateTime.now.to_i.to_s
          })
        end
        return OpenStruct.new({
          sid: nil,
          error: "iSmart: #{resp.parsed_response['Message']}"
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