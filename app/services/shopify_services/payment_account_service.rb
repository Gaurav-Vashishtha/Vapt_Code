module ShopifyServices
  class PaymentAccountService < ShopifyServices::GraphqlService
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
        {
          shopifyPaymentsAccount {
           id
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
