module SmsServices
  class TwilioSmsService < ApplicationService
    attr_reader :api_key
    attr_reader :sender_id
    attr_reader :params

    def initialize(api_key, sender_id, params)
      @api_key = api_key.split(':')
      @sender_id = sender_id
      @params = params
    end

    def call
      if !@params[:to].start_with? '+'
        @params[:to] = "+#{@params[:to]}"
      end
      response = send_request()
      parse_response(response)
    end

    private

    def build_http_client
      # You can initialize any global settings for the HTTP client if needed, but here it's not required.
      nil
    end

    def send_request
      uri = URI.parse("https://api.twilio.com/2010-04-01/Accounts/#{ENV['TWILIO_ACCOUNT_SID']}/Messages.json")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request.basic_auth( @api_key.first, @api_key.last)
      request.set_form_data(
        'From' => @sender_id,
        'To' => @params[:to],
        'Body' => @params[:body]
      )

      http.request(request)
    end

    def parse_response(response)
      if response.is_a?(Net::HTTPSuccess)
        response_data = JSON.parse(response.body)
        puts "Sent OTP.... #{response_data['sid']}"
        return OpenStruct.new(sid: response_data['sid'], error: nil)
      else
        handle_error(response)
      end
    end

    def handle_error(response)
      puts "OTP error.... #{response.body}"
      SlackNotifyJob.perform_async(":rage: *Send OTP error* Number: #{@params[:to]} \n Invalid response from Twilio: #{response.body}")

      error_message = JSON.parse(response.body)["message"] || "An error occurred."
      if error_message.include? 'phone number'
        return OpenStruct.new(sid: nil, error: I18n.t('admin.enter_valid_phone'))
      else
        return OpenStruct.new(sid: nil, error: I18n.t('admin.enable_region'))
      end
    end

  end
end