module ShopifyServices
  class PaymentFunctionCreateService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # params = ShopifyServices::PaymentFunctionCreateService.call(
    #   Shop.last
    # )

    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    def create_payment_function
      function_id = ENV['PAYMENT_FUNCTION_ID'] # 👈 from env
    
      query = @client.parse <<-'GRAPHQL'
        mutation($input: PaymentCustomizationInput!) {
          paymentCustomizationCreate(paymentCustomization: $input) {
            paymentCustomization {
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
          title: "COD King Payment Customization - Show Hide COD based on rules.",
          enabled: true,
          functionId: function_id
        }
      }
    
      resp = @client.query(query, variables: variables)
      return resp
    end
    
    

    def call
      resp = create_payment_function
      if !resp&.data&.payment_customization_create&.payment_customization&.id.blank?
        return resp&.data&.payment_customization_create&.payment_customization&.id
      else
        puts resp
        SlackNotifyJob.perform_async(
          ":rage:  (#{Rails.env})\n  *Unable to create payment function for shop #{@shop.shopify_domain} resp #{resp&.data}"
        )
        return nil
      end
    end
  end
end
