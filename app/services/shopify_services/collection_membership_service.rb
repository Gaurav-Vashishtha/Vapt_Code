module ShopifyServices
  # Returns the subset of the given product gids that belong to at least one of
  # the given collections.
  class CollectionMembershipService < ShopifyServices::GraphqlService
    BATCH = 50

    def self.call(shop, product_gids:, collection_gids:)
      shop.init_session
      new(ShopifyAPI::GraphQL.client, shop, product_gids: product_gids, collection_gids: collection_gids).call
    end

    def initialize(client, shop, product_gids:, collection_gids:)
      @client = client
      @shop = shop
      @product_gids = Array(product_gids)
      @collection_gids = Array(collection_gids)
    end

    def call
      product_ids = @product_gids.map { |g| g.to_s.split("/").last }.reject(&:blank?).uniq
      collection_ids = @collection_gids.map { |g| g.to_s.split("/").last }.reject(&:blank?)
      return [] if product_ids.empty? || collection_ids.empty?

      cols = "(" + collection_ids.map { |id| "collection_id:#{id}" }.join(" OR ") + ")"
      product_ids.each_slice(BATCH).flat_map { |slice| fetch(slice, cols) }
    end

    private

    def fetch(product_ids, cols)
      ids = "(" + product_ids.map { |id| "id:#{id}" }.join(" OR ") + ")"
      resp = @client.query(query_gql, variables: { first: product_ids.size, query: "#{ids} AND #{cols}" })
      edges = resp&.data&.products&.edges || []
      edges.map { |e| { id: e.node.id, title: e.node.title } }
    rescue => e
      Rails.logger.error("[CollectionMembershipService] shop=#{@shop&.shopify_domain} #{e.class}: #{e.message}")
      []
    end

    def query_gql
      @query_gql ||= @client.parse <<-'GRAPHQL'
        query($first: Int!, $query: String!) {
          products(first: $first, query: $query) {
            edges { node { id title } }
          }
        }
      GRAPHQL
    end
  end
end
