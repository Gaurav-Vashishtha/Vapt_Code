module ShopifyServices
    class DeliveryFunctionMetafieldReaderService < ShopifyServices::GraphqlService
      attr_reader :shop, :client, :owner_id
  
      def initialize(client, shop, owner_id)
        @client = client
        @shop = shop
        @owner_id = owner_id
      end
  
      def fetch_metafield
        query = @client.parse <<-'GRAPHQL'
          query($id: ID!) {
            deliveryCustomization(id: $id) {
              id
              metafield(namespace: "delivery-customization", key: "function-configuration") {
                id
                namespace
                key
                value
                type
              }
            }
          }
        GRAPHQL
  
        variables = { id: @owner_id }
        resp = @client.query(query, variables: variables)
        return resp
      end
  
      def call
        resp = fetch_metafield

        if resp&.data&.delivery_customization&.metafield&.value
            return JSON.parse(resp.data.delivery_customization.metafield.value.to_json)
        else
           return resp
        end
      end
    end
  end
  