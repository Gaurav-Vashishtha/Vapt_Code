module Payu
  # PayU needs four values (merchant key + salt for the classic hash APIs, OAuth
  # client_id + client_secret for Payment Links) but Setting only exposes two
  # credential columns. We pack them with ':' (same convention PhonePe already
  # uses to store salt:salt_index):
  #   payment_provider_api_key    = "<merchant_key>:<client_id>[:<merchant_id>]"
  #   payment_provider_api_secret = "<salt>:<client_secret>"
  # merchant_id defaults to merchant_key when the third segment is omitted.
  class Credentials
    SEPARATOR = ':'

    attr_reader :merchant_key, :client_id, :merchant_id, :salt, :client_secret

    def self.for(setting)
      new(setting&.payment_provider_api_key, setting&.payment_provider_api_secret)
    end

    def initialize(api_key, api_secret)
      key_parts = api_key.to_s.split(SEPARATOR).map(&:strip)
      secret_parts = api_secret.to_s.split(SEPARATOR).map(&:strip)

      @merchant_key  = key_parts[0].to_s
      @client_id     = key_parts[1].to_s
      @merchant_id   = key_parts[2].presence || @merchant_key
      @salt          = secret_parts[0].to_s
      @client_secret = secret_parts[1].to_s
    end

    def links_ready?
      merchant_key.present? && client_id.present? && client_secret.present?
    end

    def verify_ready?
      merchant_key.present? && salt.present?
    end
  end
end
