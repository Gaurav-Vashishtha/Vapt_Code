require 'digest'

module Payu
  class AccessTokenService < ApplicationService
    SCOPE = 'create_payment_links'.freeze

    def initialize(credentials)
      @credentials = credentials
    end

    def call
      return nil unless @credentials.links_ready?

      Rails.cache.fetch(cache_key, expires_in: 100.minutes, skip_nil: true) do
        resp = HTTParty.post(
          "#{Payu::Api.accounts_base}/oauth/token",
          body: {
            grant_type: 'client_credentials',
            client_id: @credentials.client_id,
            client_secret: @credentials.client_secret,
            scope: SCOPE
          },
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
          timeout: 20
        )
        unless resp.success?
          Rails.logger.error("[payu/oauth] token HTTP #{resp.code}: #{resp.body}")
          next nil
        end

        token = JSON.parse(resp.body || '{}')['access_token'].presence
        Rails.logger.error("[payu/oauth] no access_token in response: #{resp.body}") if token.nil?
        token
      end
    rescue => e
      Rails.logger.error("[payu/oauth] token fetch failed: #{e.class}: #{e.message}")
      nil
    end

    private

    def cache_key
      "payu/oauth_token/#{Digest::MD5.hexdigest(@credentials.client_id.to_s)}"
    end
  end
end
