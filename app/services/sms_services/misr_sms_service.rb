# app/services/sms_services/misr_sms_service.rb

module SmsServices
    class MisrSmsService < ApplicationService
      attr_reader :username, :password, :template_id, :environment, :sender_id, :params
  
      # Usage:
      # api_key = "username:password:template_id:environment"
      # sender_id = "sender_hash"
      # params = { to: "201018885188", body: "1234" }
      #
      # SmsServices::MisrSmsService.call(api_key, sender_id, params)
  
      def initialize(api_key, sender_id, params)
        credentials   = api_key.split(':')
        @username     = credentials[0]
        @password     = credentials[1]
        @template_id  = credentials[2]
        @environment  = credentials[3] || '1'
        @sender_id    = sender_id
        @params       = params
      end
  
      def call
        begin
          uri = URI.parse("https://smsmisr.com/api/SMS/")
          request = Net::HTTP::Post.new(uri)
          request.set_form_data(
            "environment" => environment,
            "username"    => username,
            "password"    => password,
            "sender"      => sender_id,
            "mobile"      => params[:to],
            "message"     => params[:body],
            "language"     => 1
          )
          
          req_options = { use_ssl: uri.scheme == "https" }
  
          response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
            http.request(request)
          end
  
          parsed_response = JSON.parse(response.body) rescue {}
  
          if response.code.to_i == 200 
            OpenStruct.new({
              sid: "smsmisr:#{parsed_response['SMSID']}",
              response: parsed_response
            })
          else
            OpenStruct.new({
              sid: nil,
              error: parsed_response.presence || response.body
            })
          end
        rescue => e
          OpenStruct.new({
            sid: nil,
            error: "Exception: #{e.message}"
          })
        end
      end
    end
  end
  