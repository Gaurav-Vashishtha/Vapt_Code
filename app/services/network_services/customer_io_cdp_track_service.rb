# frozen_string_literal: true

module NetworkServices
  # Calls Customer.io CDP Identify API (v1) to identify a user and set traits.
  # API key is Base64-encoded for Basic auth.
  # Set ENV['CUSTOMER_IO_CDP_API_KEY'] or pass api_key to .call.
  #
  # Sample call:
  #   NetworkServices::CustomerIoCdpTrackService.call(
  #     userId: "97980cfea0068",
  #     traits: {
  #       name: "Avijeet Person",
  #       email: "avijeetdey.email@gmail.com"
  #     }
  #   )
  #
  # With explicit API key (optional):
  #   NetworkServices::CustomerIoCdpTrackService.call(
  #     { userId: "user_12345", traits: { name: "John", email: "john@example.com" } },
  #     api_key: "your_api_key"
  #   )
  class CustomerIoCdpTrackService
    IDENTIFY_URL = "https://cdp.customer.io/v1/identify"

    def initialize(api_key: nil)
      @api_key = api_key.presence || ENV["CUSTOMER_IO_CDP_API_KEY"]
    end

    # Identify a user with traits.
    # Payload: :userId (required), :traits (hash, e.g. name, email).
    # Returns { success: true, code:, body: } or { success: false, error: }
    # Supports both .call(userId: "...", traits: {}) and .call({ userId: "...", traits: {} }, api_key: nil).
    def self.call(payload = {}, api_key: nil, **keyword_payload)
      payload = keyword_payload.empty? ? payload : keyword_payload
      new(api_key: api_key).identify(payload)
    end

    def identify(payload)
      return { success: false, error: "Customer.io CDP API key not set" } if @api_key.blank?

      body = build_body(payload)
      uri = URI(IDENTIFY_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Basic #{base64_credentials}"
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      response = http.request(request)
      result = { success: response.is_a?(Net::HTTPSuccess), code: response.code.to_i, body: response.body.presence }
      result[:error] = response.body if result[:success] == false
      result
    rescue StandardError => e
      Rails.logger.error "CustomerIoCdpTrackService error: #{e.message}"
      { success: false, error: e.message }
    end

    private

    def base64_credentials
      Base64.strict_encode64(@api_key.to_s.strip)
    end

    def build_body(payload)
      payload = payload.deep_stringify_keys
      {
        "userId" => payload["userId"],
        "traits" => payload["traits"].presence || {}
      }
    end
  end
end
