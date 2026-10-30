module ShopifyServices

  #   params = ShopifyServices::PaymentMethodGetService.call(
  #   Shop.last
  # )

  class PaymentMethodGetService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    def get_payment_methods
      query = @client.parse <<-'GRAPHQL'
      {
        translatableResources(resourceType:PAYMENT_GATEWAY,first:20){
          __typename
          nodes{
            translatableContent{
              value
              locale
            }
          }
        }
        }
      GRAPHQL
      variables = {
      }
      return @client.query(query, variables: variables)
    end




    def call
      resp = get_payment_methods
      payment_methods = []
      if resp.data&.translatable_resources&.nodes.length > 0
        resp.data&.translatable_resources&.nodes.each do |node|
          payment_methods.push({value: node.translatable_content.first.value, label:node.translatable_content.first.value})
        end
      end
      return payment_methods
    end
  end
end
