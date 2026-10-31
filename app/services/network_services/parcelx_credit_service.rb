module NetworkServices
  # Reads the ParcelX prepaid balance from the `x-remaining-credits` response
  # header. ParcelX exposes no balance endpoint, so this makes one ordinary
  # address lookup purely for its headers — the probe itself costs a credit.
  #
  #   NetworkServices::ParcelxCreditService.call #=> 49964 or nil
  class ParcelxCreditService < ApplicationService
    DEFAULT_PROBE_PHONE = '9130751989'.freeze
    CREDIT_HEADER = 'x-remaining-credits'.freeze

    attr_reader :phone

    def initialize(phone = nil)
      @phone = phone.presence || ENV.fetch("PARCELX_CREDIT_PROBE_PHONE", nil).presence || DEFAULT_PROBE_PHONE
    end

    def call
      resp = HTTParty.get(
        "#{ParcelxAddressService::BASE_URL}#{ParcelxAddressService::PATH}",
        query: { phone: phone },
        headers: { 'X-api-key' => ParcelxAddressService.api_key },
        timeout: 10
      )

      unless resp.success?
        Rails.logger.warn("[parcelx_credits] probe HTTP #{resp.code}: #{resp.body}")
        return nil
      end

      raw = resp.headers[CREDIT_HEADER]
      if raw.blank?
        Rails.logger.warn("[parcelx_credits] response carried no #{CREDIT_HEADER} header")
        return nil
      end

      credits = Integer(raw.to_s.strip, exception: false)
      Rails.logger.warn("[parcelx_credits] non-numeric #{CREDIT_HEADER}=#{raw.inspect}") if credits.nil?
      credits
    rescue => e
      Rails.logger.warn("[parcelx_credits] probe failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
