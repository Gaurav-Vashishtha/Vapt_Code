module ShopifyServices
    class DiscountAutomaticAppCreateService < ShopifyServices::GraphqlService
      attr_reader :shop, :client, :title, :function_id, :starts_at, :discount_classes
  
      # Usage from Rails console:
      # shop = Shop.find_by(shopify_domain: 'your-shop.myshopify.com')
    #   ShopifyServices::DiscountAutomaticAppCreateService.call(
    #     shop,
    #     title: "Automatic 20% Storewide",
    #     function_id: "019b6576-e4ee-7add-805a-1e27ea394404",
    #     discount_classes: ["ORDER","PRODUCT"], # Required for discount functions
    #     starts_at: "2024-01-01T00:00:00Z"
    #   )
  
      # Prefer service-specific class method to avoid relying on base kwargs
      def self.call(shop, title:, function_id:, discount_classes: ["ORDER"], combines_with: nil, starts_at: nil)
        shop.init_session()
        client = ShopifyAPI::GraphQL.client
        new(client, shop, title: title, function_id: function_id, discount_classes: discount_classes, combines_with: combines_with, starts_at: starts_at).call
      end

      def initialize(client, shop, title:, function_id:, discount_classes: ["ORDER"], combines_with: nil, starts_at: nil)
        @client = client
        @shop = shop
        @title = title
        @function_id = function_id
        @discount_classes = discount_classes.is_a?(Array) ? discount_classes : [discount_classes]
        @combines_with = combines_with
        @starts_at = starts_at || Time.current.utc.iso8601
      end
  
      def create_automatic_app_discount
        query = @client.parse <<-'GRAPHQL'
          mutation($automaticAppDiscount: DiscountAutomaticAppInput!) {
            discountAutomaticAppCreate(automaticAppDiscount: $automaticAppDiscount) {
              automaticAppDiscount {
                discountId
                title
                appDiscountType {
                  functionId
                }
              }
              userErrors {
                field
                message
              }
            }
          }
        GRAPHQL
  
        input = {
          title: @title,
          startsAt: @starts_at,
          functionId: @function_id,
          discountClasses: @discount_classes
        }
        input[:combinesWith] = @combines_with if @combines_with.present?

        resp = @client.query(query, variables: { automaticAppDiscount: input })
        resp
      end
  
      def call
        create_automatic_app_discount
      end
    end
  end
  
