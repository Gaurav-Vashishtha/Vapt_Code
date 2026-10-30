module Cashfree
  # Cashfree Payment Links authenticate with two values only:
  #   x-client-id     = App ID
  #   x-client-secret = Secret Key
  # These map 1:1 onto Setting's two credential columns, so (unlike PayU) no
  # ':' packing is needed.
  #   payment_provider_api_key    = "<App ID>"
  #   payment_provider_api_secret = "<Secret Key>"
  class Credentials
    attr_reader :client_id, :client_secret

    def self.for(setting)
      new(setting&.payment_provider_api_key, setting&.payment_provider_api_secret)
    end

    def initialize(api_key, api_secret)
      @client_id     = api_key.to_s.strip
      @client_secret = api_secret.to_s.strip
    end

    def ready?
      client_id.present? && client_secret.present?
    end

    def headers
      {
        'x-client-id' => client_id,
        'x-client-secret' => client_secret,
        'x-api-version' => Cashfree::Api::API_VERSION,
        'Content-Type' => 'application/json'
      }
    end
  end
end
