module NetworkServices
  # Looks up saved address record(s) for a customer by phone number via the
  # ParcelX "Vega" address-intelligence API.
  #
  #   GET https://iq.parcelx.in/vega/address?phone=<10-digit>
  #   header: X-api-key: <key>
  #
  # Returns the parsed JSON array of address hashes on success, or [] on any
  # failure (bad phone, non-2xx, network/parse error) so callers never crash.
  #
  #   NetworkServices::ParcelxAddressService.call('9871485508')
  class ParcelxAddressService < ApplicationService
    BASE_URL = 'https://iq.parcelx.in'.freeze
    PATH     = '/vega/address'.freeze

    attr_reader :phone

    # Production must use the ENV key; the raise is caught by the blanket
    # rescue in #call so a missing key fails safe (returns []) with a log line.
    def self.api_key
      key = ENV.fetch("PARCELX_API_KEY", nil).presence
      return key if key
      raise KeyError, 'PARCELX_API_KEY is not set' if Rails.env.production?

      'xcel_live_Aw6CtS2EK9-zGuIwx6wsmLAcK6UZlJp7'
    end

    def initialize(phone)
      @phone = phone
    end

    def call
      number = normalize_phone(phone)
      if number.length != 10
        Rails.logger.warn("[parcelx_address] invalid phone=#{phone.inspect}")
        return []
      end

      resp = HTTParty.get(
        "#{BASE_URL}#{PATH}",
        query: { phone: number },
        headers: { 'X-api-key' => api_key },
        timeout: 5
      )

      unless resp.success?
        Rails.logger.warn("[parcelx_address] phone=#{number} HTTP #{resp.code}: #{resp.body}")
        return []
      end

      body = resp.parsed_response
      body.is_a?(Array) ? body : []
    rescue => e
      Rails.logger.warn("[parcelx_address] phone=#{phone.inspect} lookup failed: #{e.class}: #{e.message}")
      []
    end

    private

    # ParcelX wants a bare 10-digit number. Strip symbols and drop a leading
    # country code (e.g. +91 / 0091) by keeping the last 10 digits.
    def normalize_phone(value)
      digits = value.to_s.gsub(/\D/, '')
      digits.length > 10 ? digits.last(10) : digits
    end

    def api_key
      self.class.api_key
    end
  end
end
