# frozen_string_literal: true

module ShopifyServices
  # Fetch the current app's Admin GraphQL App GID and numeric id.
  #
  # Visitor API requires the numeric App ID (from `query { app { id } }`):
  #   gid://shopify/App/123456789  ->  123456789
  #
  # Usage:
  #   ShopifyServices::AppIdFetchService.call(shop)
  #   # => { ok: true, gid: "gid://shopify/App/123", app_id: "123" }
  class AppIdFetchService < ShopifyServices::GraphqlService
    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    def call
      query = @client.parse(<<~GRAPHQL)
        query {
          app {
            id
            title
          }
        }
      GRAPHQL

      resp = @client.query(query)
      gid = resp&.data&.app&.id.to_s
      title = resp&.data&.app&.title.to_s

      app_id = gid[%r{\Agid://shopify/App/(\d+)\z}, 1]

      if gid.blank?
        return { ok: false, error: "blank_gid", gid: nil, app_id: nil, title: nil }
      end

      if app_id.blank?
        return { ok: false, error: "unexpected_gid_format", gid: gid, app_id: nil, title: title.presence }
      end

      { ok: true, gid: gid, app_id: app_id, title: title.presence }
    rescue StandardError => e
      Rails.logger.warn "[AppIdFetchService] shop_id=#{@shop.id} #{@shop.shopify_domain}: #{e.class}: #{e.message}"
      { ok: false, error: e.message, gid: nil, app_id: nil, title: nil }
    end
  end
end

