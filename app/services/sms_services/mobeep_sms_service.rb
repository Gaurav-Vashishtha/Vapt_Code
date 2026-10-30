
require 'net/http'
require 'json'
require 'ostruct'
require 'uri'


# api_key = "MNotDir1:*hXjW9Ob"  # Example: username:password
# sender_id = "FACEBOOK"
# params = {
#   to: "201080885400",  # Recipient phone number
#   body: "hello"       # SMS body
# }

# mobeep_service = SmsServices::MobeepSmsService.new(api_key, sender_id, params)

# response = mobeep_service.call

# if response.sid
#   puts "Message sent successfully with SID: #{response.sid}"
# else
#   puts "Failed to send the message: #{response.error}"
# end

module SmsServices
  class MobeepSmsService < ApplicationService
    attr_reader :username, :password, :sender_id, :params

    def initialize(api_key, sender_id, params)
      @username = api_key.split(':')[0]
      @password = api_key.split(':')[1]
      @sender_id = sender_id
      @params = params
    end

    def call
      begin
        uri = URI.parse("https://globalsms.mobeep.io:1443/cgi-bin/sendsms")
        request_url = URI::HTTP.build(
          host: uri.host,
          port: uri.port,
          path: uri.path,
          query: URI.encode_www_form({
            username: @username,
            password: @password,
            from: @sender_id,
            to: @params[:to],
            text: @params[:body]
          })
        ).to_s

        # Set up the HTTP connection
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # Disable SSL verification for testing

        # Send the GET request
        response = http.get(URI.parse(request_url))
        response_parts = response.body.strip.split("\n")

        # We expect the response to contain the message ID on the first line
        if response_parts.size >= 1
          message_id = response_parts[0]  # First part is the message ID
          return OpenStruct.new({
            sid: message_id  # Set the message ID as SID
          })
        else
          return OpenStruct.new({
            sid: nil,
            error: "Unexpected response format: #{response.body}"
          })
        end
      rescue StandardError => e
        return OpenStruct.new({
          sid: nil,
          error: e.message
        })
      end
    end
  end
end