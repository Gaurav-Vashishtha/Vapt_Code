# frozen_string_literal: true

module ShopifyServices
  # Fetches total customer count from Shopify for a shop.
  # Call: ShopifyServices::CustomerCountFetchService.call(shop) => Integer or nil
  class CustomerCountFetchService < ShopifyServices::GraphqlService
    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    def call
      # As of Admin GraphQL 2025-07, `limit: null` returns an uncapped count.
      query = @client.parse(<<~GRAPHQL)
        query {
          customersCount(limit: null) {
            count
          }
        }
      GRAPHQL
      resp = @client.query(query)
      return nil if resp.blank? || resp.data.blank?

      resp.data.customers_count&.count
    rescue => e
      Rails.logger.warn "[CustomerCountFetchService] #{@shop.shopify_domain}: #{e.message}"
      nil
    end
  end
end
