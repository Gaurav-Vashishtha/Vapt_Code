module ShopifyServices
  class DeliveryFunctionCreateService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # params = ShopifyServices::PaymentFunctionCreateService.call(
    #   Shop.last
    # )

    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    def create_delivery_function
      function_id = ENV.fetch("DELIVERY_FUNCTION_ID", nil) # 👈 Read from ENV
    
      query = @client.parse <<-'GRAPHQL'
        mutation($input: DeliveryCustomizationInput!) {
          deliveryCustomizationCreate(deliveryCustomization: $input) {
            deliveryCustomization {
              id
            }
            userErrors {
              message
            }
          }
        }
      GRAPHQL
    
      variables = {
        input: {
          functionId: function_id,
          title: "Customize shipping rates from COD-King",
          enabled: true
        }
      }
    
      resp = @client.query(query, variables: variables)
      puts "#{resp.inspect}"
      return resp
    end
    

    def call
      resp = create_delivery_function
      if !resp&.data&.delivery_customization_create&.delivery_customization&.id.blank?
        return resp&.data&.delivery_customization_create&.delivery_customization&.id
      else
        puts resp
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Unable to create delivery function for shop #{@shop.shopify_domain} resp #{resp&.data}"
        )
        return nil
      end
    end
  end
end
