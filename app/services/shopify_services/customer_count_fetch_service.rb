# frozen_string_literal: true

module ShopifyServices
  # Fetches total customer count from Shopify for a shop.
  # Call: ShopifyServices::CustomerCountFetchService.call(shop) => Integer or nil
  # Call: ShopifyServices::CustomerCountFetchService.call(shop, time) => customers created at or after time
  class CustomerCountFetchService < ShopifyServices::GraphqlService
    Result = Struct.new(:count, :unauthorized, keyword_init: true)

    def self.fetch(shop, created_since = nil)
      shop.init_session
      new(ShopifyAPI::GraphQL.client, shop, created_since).fetch
    end

    def initialize(client, shop, created_since = nil)
      @client = client
      @shop = shop
      @created_since = created_since
    end

    def call
      fetch.count
    end

    def fetch
      # As of Admin GraphQL 2025-07, `limit: null` returns an uncapped count.
      query = @client.parse(<<~GRAPHQL)
        query {
          customersCount(limit: null#{created_since_argument}) {
            count
          }
        }
      GRAPHQL
      resp = @client.query(query)
      return Result.new(count: nil, unauthorized: false) if resp.blank? || resp.data.blank?

      Result.new(count: resp.data.customers_count&.count, unauthorized: false)
    rescue => e
      Rails.logger.warn "[CustomerCountFetchService] #{@shop.shopify_domain}: #{e.message}"
      Result.new(count: nil, unauthorized: CustomerSyncState.unauthorized_message?(e.message))
    end

    private

    def created_since_argument
      return '' if @created_since.blank?

      %(, query: "created_at:>='#{@created_since.utc.iso8601}'")
    end
  end
end
