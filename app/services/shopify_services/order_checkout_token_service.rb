module ShopifyServices
  class OrderCheckoutTokenService  < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # params = ShopifyServices::OrderCheckoutTokenService.call(
    #   Shop.last,
    #   OrderConfirmation.last.order_id
    # )

    def initialize( client, shop, order_id)
      @client = client
      @shop = shop
      @order_id = order_id
    end

    def call
      if !@order_id.blank?
        @shop.init_session
        shopify_order = ShopifyAPI::Order.find(@order_id)
        if !shopify_order.blank?
          order_confirmation = OrderConfirmation.find_by(order_id: @order_id)
          return order_confirmation.update(checkout_token: shopify_order.checkout_token)
        end
      end
    end

  end
end
