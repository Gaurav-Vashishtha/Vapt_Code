module ShopifyServices
    class ProductDeleteService < ShopifyServices::GraphqlService
      attr_reader :shop, :client

      # ShopifyServices::ProductDeleteService.call(@shop, 'gid://shopify/Product/9739260494137')
  
      def initialize(client, shop, product_id)
        @client = client
        @shop = shop
        @product_id = product_id
      end

      def delete_product(product_id)
        query = @client.parse <<-'GRAPHQL'
        mutation($id:ID!) {
          productDelete(input: {id: $id}) {
            deletedProductId
            userErrors {
              field
              message
            }
          }
        }
        GRAPHQL
  
        variables = {
          id: product_id,
        }
        @client.query(query, variables: variables)
      end

  
      def call
        return delete_product(@product_id)
      end
    end
  end