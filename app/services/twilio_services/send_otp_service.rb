require 'net/http'
require 'uri'
require 'json'
require 'ostruct'

module TwilioServices
  class SendOtpService
    IVORY_COAST_CC = '225'
    IVORY_COAST_ISO = 'CI'

    def self.call(params)
      new(params).call
    end

    def initialize(params)
      @params = params.to_h.with_indifferent_access
    end

    def call
      normalize_ivory_coast_to!
      to = @params[:to].to_s.strip
      @params[:to] = to.start_with?('+') ? to : "+#{to}"

      response = send_request
      parse_response(response)
    end

    private

    def ivory_coast_country_code?
      cc = @params[:country_code].to_s.gsub(/\s+/, '').delete_prefix('+').upcase
      cc == IVORY_COAST_CC || cc == IVORY_COAST_ISO
    end

    # Côte d'Ivoire (+225): national numbers use a leading 0; ensure it is present before the local part.
    def normalize_ivory_coast_to!
      return unless ivory_coast_country_code?

      raw = @params[:to].to_s
      return if raw.blank?

      without_plus = raw.gsub(/\s/, '').delete_prefix('+')
      national =
        if without_plus.start_with?(IVORY_COAST_CC)
          without_plus[IVORY_COAST_CC.length..]
        else
          without_plus
        end

      national = national.gsub(/\D/, '')
      return if national.blank?

      national = "0#{national}" unless national.start_with?('0')
      @params[:to] = "+#{IVORY_COAST_CC}#{national}"
    end

    def send_request
      uri = URI.parse("https://api.twilio.com/2010-04-01/Accounts/#{ENV['TWILIO_ACCOUNT_SID']}/Messages.json")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request.basic_auth(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])

      request.set_form_data(
        'From' => @params[:from],
        'To' => @params[:to],
        'Body' => @params[:body]
      )

      http.request(request)
    end

    def parse_response(response)
      if response.is_a?(Net::HTTPSuccess)
        response_data = JSON.parse(response.body)
        puts "Sent OTP.... #{response_data['sid']}"
        return OpenStruct.new(sid: response_data['sid'], error: nil, twilio_detail: nil)
      else
        handle_error(response)
      end
    end

    def twilio_error_payload(body)
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      { 'message' => body.to_s.strip.truncate(1000) }
    end

    def handle_error(response)
      raw_body = response.body.to_s
      puts "OTP error.... #{raw_body}"

      SlackNotifyJob.perform_async(":rage: *Send OTP error* Number: #{@params[:to]} \n Invalid response from Twilio: #{raw_body.truncate(2500)}")

      parsed = twilio_error_payload(raw_body)
      twilio_message = [
        parsed['message'],
        parsed['more_info'] && "(#{parsed['more_info']})",
      ].compact.join(' ').presence

      detail =
        if parsed['code'].present?
          "#{twilio_message || raw_body.strip.truncate(500)} [Twilio #{parsed['code']}]"
        else
          twilio_message || raw_body.strip.truncate(500).presence || 'An error occurred.'
        end

      detail = "#{detail} (HTTP #{response.code})" if response.respond_to?(:code) && response.code.present?

      user_facing =
        if detail.to_s.downcase.include?('phone number')
          I18n.t('admin.enter_valid_phone')
        else
          I18n.t('admin.enable_region')
        end

      OpenStruct.new(sid: nil, error: user_facing, twilio_detail: detail)
    end
  end
end
