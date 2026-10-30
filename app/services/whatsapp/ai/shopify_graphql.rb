# frozen_string_literal: true

module Whatsapp
  module Ai
    module ShopifyGraphql
      class Error < StandardError; end

      TIMEOUT = 20

      module_function

      def call(shop, query, variables = {})
        shop.init_session
        response = HTTParty.post(
          "https://#{shop.shopify_domain}/admin/api/#{api_version(shop)}/graphql.json",
          headers: { 'X-Shopify-Access-Token' => shop.shopify_token.to_s, 'Content-Type' => 'application/json' },
          body: { query: query, variables: variables }.to_json,
          timeout: TIMEOUT
        )
        data = JSON.parse(response.body.to_s.presence || '{}')
        raise Error, "Shopify HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

        errors = Array(data['errors'])
        raise Error, errors.map { |e| e.is_a?(Hash) ? e['message'] : e.to_s }.join('; ') if errors.any?

        data['data'] || {}
      rescue JSON::ParserError
        raise Error, 'Shopify returned an unreadable response'
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
        raise Error, "Could not reach Shopify: #{e.class}"
      end

      def api_version(shop)
        shop.respond_to?(:api_version) && shop.api_version.present? ? shop.api_version : ShopifyApp.configuration.api_version
      end
    end
  end
end
