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
      return if @order_id.blank?
      attempts = 0
      begin
        @shop.init_session
        shopify_order = ShopifyAPI::Order.find(@order_id)
        if !shopify_order.blank?
          order_confirmation = OrderConfirmation.find_by(order_id: @order_id)
          return order_confirmation.update(checkout_token: shopify_order.checkout_token)
        end
      rescue ActiveResource::UnauthorizedAccess
        # Best-effort enrichment: the order is already saved, so a revoked token
        # must not fail the order/create webhook job.
        attempts += 1
        if attempts == 1 && ShopifyServices::OfflineTokenService.recover_from_unauthorized!(@shop, failed_token: @shop.shopify_token)
          retry
        end
        @shop.notify_token_reauth_needed_once("401 on Order.find (order_id=#{@order_id}) — token revoked out of band")
        nil
      end
    end

  end
end
