module ShopifyServices
  class PaymentFunctionGetService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # params = ShopifyServices::PaymentFunctionGetService.call(
    #   Shop.last
    # )

    def initialize(client, shop)
      @client = client
      @shop = shop
      
    end

    def get_payment_function
      query = @client.parse <<-'GRAPHQL'
      query {
        paymentCustomizations(first: 100) {
          edges {
            node {
              id
              title
            }
          }
        }
      }
      GRAPHQL
      variables = {
      }
      resp = @client.query(query, variables: variables)
      return resp
    end

    def call
      resp = get_payment_function
      puts resp
    end
  end
end
