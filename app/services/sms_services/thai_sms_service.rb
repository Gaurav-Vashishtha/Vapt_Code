require 'net/http'
require 'uri'
require 'json'



module SmsServices
  class ThaiSmsService < ApplicationService
    attr_reader :api_key, :sender_id, :params

    def initialize(api_key, sender_id, params)
      # Normalize API key: strip all whitespace/newlines and ensure "Basic " prefix
      # Handle cases where "Basic" and base64 string might be on separate lines
      normalized_key = api_key.to_s.gsub(/\s+/, '').strip
      # Remove "Basic" prefix if present (case-insensitive) to avoid duplication
      normalized_key = normalized_key.sub(/^basic/i, '')
      @api_key = "Basic #{normalized_key}"
      @sender_id = sender_id
      @params = params
    end

    def call
      begin
        uri = URI.parse("https://api-v2.thaibulksms.com/sms")

        msisdn_value = formatted_msisdn(@params[:to])

        # Build form-urlencoded body with URL encoding (same as --data-urlencode)
        encoded_data = URI.encode_www_form(
          msisdn: msisdn_value,
          force: 'corporate',
          message: @params[:body],
          sender: @sender_id,
          expire: '00:05'
        )

        request = Net::HTTP::Post.new(uri)
        request["accept"] = "application/json"
        request["authorization"] = @api_key

        request["content-type"] = "application/x-www-form-urlencoded"
        request.body = encoded_data

        req_options = { use_ssl: uri.scheme == "https" }

        response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
          http.request(request)
        end

        parsed_response = JSON.parse(response.body)
        puts "Thai SMS response: #{parsed_response}"

        if parsed_response["phone_number_list"] && parsed_response["phone_number_list"].any?
          OpenStruct.new({
            sid: "thai_sms:#{parsed_response["phone_number_list"].first["message_id"]}",
            used_credit: parsed_response["total_use_credit"],
            remaining_credit: parsed_response["remaining_credit"]
          })
        else
          OpenStruct.new({
            sid: nil,
            error: parsed_response["error"] || parsed_response
          })
        end
      rescue => e
        OpenStruct.new({
          sid: nil,
          error: e.message
        })
      end
    end
    private

    # ThaiBulkSMS expects local format (leading 0) even if we store numbers in E.164.
    def formatted_msisdn(raw_number)
      digits = raw_number.to_s.gsub(/\D/, '')
      return digits if digits.blank?

      if digits.start_with?('66')
        local = digits.sub(/^66/, '')
        local = local.sub(/^0+/, '')
        "0#{local}"
      elsif digits.start_with?('0')
        digits
      else
        digits
      end
    end
  end
end
