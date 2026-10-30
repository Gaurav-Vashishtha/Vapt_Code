module ShopifyServices
  class ProductGetService < ShopifyServices::GraphqlService

    # Example: ShopifyServices::ProductGetService.call(@shop)

    attr_reader :shop, :client

    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    def get_products(first: 10)
      query = @client.parse <<-'GRAPHQL' 
        query ($first: Int!, $query: String!) {
          products(first: $first, query: $query) {
            edges {
              node {
                id
                title
                handle
                status
              }
              cursor
            }
            pageInfo {
              hasNextPage
            }
          }
        }
      GRAPHQL

      variables = {
        first: first,
        query: "status:active"
      }

      resp = @client.query(query, variables: variables)

      return resp.data.products.edges if resp&.data&.products&.edges.present?

      nil
    end

    def call
      resp = get_products
      
      # Handle case when no products are found or query fails
      if resp.nil? || resp.empty? || resp[0].nil? || resp[0].node.nil? || resp[0].node.handle.nil?
        return nil
      end
      
      product_url = "https://#{@shop.shopify_domain}/products/#{resp[0].node.handle}"
      puts product_url
      return product_url
    end
  end
end
