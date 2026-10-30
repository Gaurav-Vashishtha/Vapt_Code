module ShopifyServices
    class PaymentFunctionMetafieldReaderService < ShopifyServices::GraphqlService
      attr_reader :shop, :client, :owner_id
  
      def initialize(client, shop, owner_id)
        @client = client
        @shop = shop
        @owner_id = owner_id
      end
  
      def fetch_metafield
        query = @client.parse <<-'GRAPHQL'
          query($id: ID!) {
            paymentCustomization(id: $id) {
              id
              metafield(namespace: "payment-customization", key: "function-configuration") {
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
        if resp&.data&.payment_customization&.metafield&.value
            return JSON.parse(resp.data.payment_customization.metafield.value.to_json)
        else
           return resp
        end
      end
    end
  end
  