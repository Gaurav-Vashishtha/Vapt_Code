module ShopifyServices
    class CartTransformCreateService < ShopifyServices::GraphqlService
      attr_reader :shop, :client
  
      def initialize(client, shop)
        @client = client
        @shop = shop
      end
  
      def create_cart_transform
        # You need the function ID, not handle
        function_id = ENV['CART_TRANSFORM_FUNCTION_ID'] #'019a2974-8599-7393-b606-05f6d6a25399' for production Should be like "01J5XXXXXXXXXXXXXX"
      
        query = @client.parse <<-'GRAPHQL'
          mutation($functionId: String!, $blockOnFailure: Boolean) {
            cartTransformCreate(
              functionId: $functionId
              blockOnFailure: $blockOnFailure
            ) {
              cartTransform {
                id
                functionId
                blockOnFailure
              }
              userErrors {
                field
                message
                code
              }
            }
          }
        GRAPHQL
      
        variables = {
          functionId: function_id,  # Changed from functionHandle to functionId
          blockOnFailure: true
        }
      
        resp = @client.query(query, variables: variables)
        return resp
      end
  
      def call
        resp = create_cart_transform
        
        if resp&.data&.cart_transform_create&.cart_transform&.id.present?
          cart_transform_id = resp.data.cart_transform_create.cart_transform.id
          
          Rails.logger.info "Cart transform created successfully for shop #{@shop.shopify_domain}: #{cart_transform_id}"
          
          return cart_transform_id
        else
          error_messages = resp&.data&.cart_transform_create&.user_errors&.map(&:message)&.join(', ')
          
          Rails.logger.error "Failed to create cart transform for shop #{@shop.shopify_domain}: #{resp.inspect}"
          
          SlackNotifyJob.perform_async(
            ":rage: (#{Rails.env})\n *Unable to create cart transform for shop #{@shop.shopify_domain}*\n Errors: #{resp}"
          )
          
          return nil
        end
      end
    end
  end