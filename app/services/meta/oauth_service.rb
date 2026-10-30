require 'httparty'

module Meta
  class OauthService < ApplicationService
    class Error < StandardError; end

    OAUTH_HOST = 'https://graph.facebook.com'.freeze

    def initialize(code:)
      @code = code
      @app_id = ENV.fetch('META_APP_ID')
      @app_secret = ENV.fetch('META_APP_SECRET')
      @version = ENV.fetch('META_GRAPH_API_VERSION', 'v22.0')
    end

    def call
      exchange_code_for_token
    end

    private

    attr_reader :code, :app_id, :app_secret, :version

    def exchange_code_for_token
      response = HTTParty.get(
        "#{OAUTH_HOST}/#{version}/oauth/access_token",
        query: {
          client_id: app_id,
          client_secret: app_secret,
          code: code
        }
      )

      parsed = JSON.parse(response.body || '{}')

      unless response.success?
        Rails.logger.warn("[meta/oauth] code exchange failed: #{response.body}")
        raise Error, parsed.dig('error', 'message') || 'OAuth code exchange failed'
      end

      {
        access_token: parsed['access_token'],
        token_type: parsed['token_type'],
        expires_in: parsed['expires_in']
      }
    end
  end
end
