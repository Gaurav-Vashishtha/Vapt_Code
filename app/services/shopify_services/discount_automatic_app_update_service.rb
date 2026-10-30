module ShopifyServices
  class DiscountAutomaticAppUpdateService < ShopifyServices::GraphqlService
    attr_reader :shop, :client, :discount_gid, :combines_with, :discount_classes, :title

    # Usage from Rails console:
    #   shop = Shop.find_by(shopify_domain: 'your-shop.myshopify.com')
    #   ShopifyServices::DiscountAutomaticAppUpdateService.call(
    #     shop,
    #     discount_gid: "gid://shopify/DiscountAutomaticNode/123",
    #     combines_with: { order: true, product: true, shipping: false }
    #   )
    def self.call(shop, discount_gid:, combines_with: nil, discount_classes: nil, title: nil)
      shop.init_session()
      client = ShopifyAPI::GraphQL.client
      new(client, shop, discount_gid: discount_gid, combines_with: combines_with, discount_classes: discount_classes, title: title).call
    end

    def initialize(client, shop, discount_gid:, combines_with: nil, discount_classes: nil, title: nil)
      @client = client
      @shop = shop
      @discount_gid = discount_gid
      @combines_with = combines_with
      @discount_classes = discount_classes
      @title = title
    end

    def update_automatic_app_discount
      query = @client.parse <<-'GRAPHQL'
        mutation($id: ID!, $automaticAppDiscount: DiscountAutomaticAppInput!) {
          discountAutomaticAppUpdate(id: $id, automaticAppDiscount: $automaticAppDiscount) {
            automaticAppDiscount {
              discountId
              title
              discountClasses
              combinesWith {
                orderDiscounts
                productDiscounts
                shippingDiscounts
              }
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      input = {}
      input[:title] = @title if @title.present?
      input[:discountClasses] = Array(@discount_classes) if @discount_classes.present?
      input[:combinesWith] = combines_with_input if combines_with_input.present?

      @client.query(query, variables: { id: @discount_gid, automaticAppDiscount: input })
    end

    def call
      update_automatic_app_discount
    end

    private

    def combines_with_input
      return @combines_with_input if defined?(@combines_with_input)

      @combines_with_input =
        if @combines_with.blank?
          nil
        else
          cw = @combines_with.symbolize_keys
          {
            orderDiscounts: !!(cw.key?(:orderDiscounts) ? cw[:orderDiscounts] : cw[:order]),
            productDiscounts: !!(cw.key?(:productDiscounts) ? cw[:productDiscounts] : cw[:product]),
            shippingDiscounts: !!(cw.key?(:shippingDiscounts) ? cw[:shippingDiscounts] : cw[:shipping])
          }
        end
    end
  end
end
