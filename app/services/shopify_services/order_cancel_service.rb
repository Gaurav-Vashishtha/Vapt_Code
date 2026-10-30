require 'securerandom'

module ShopifyServices
  class OrderCancelService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop, order_id)
      @client = client
      @shop = shop
      @order_id = order_id
    end

    def call
      order_confirmation = OrderConfirmation.find_by(order_id: @order_id)
      if order_confirmation
        query = @client.parse <<-'GRAPHQL'
        mutation ($orderId: ID!, $refund: Boolean!, $restock: Boolean!, $reason: OrderCancelReason!, $sendNotification: Boolean!) {
            OrderCancel(
              orderId: $orderId
              refund: $refund
              restock: $restock
              reason: $reason
              sendNotification: $sendNotification
            ) {
              job {
                id
                done
                __typename
              }
              userErrors {
                field
                message
                __typename
              }
              __typename
            }
          }
        GRAPHQL
        
        variables = {
            orderId: "gid://shopify/Order/5219531161873",
            refund: true,
            restock: true,
            reason: "DECLINED",
            sendNotification: false
        }
        resp = @client.query(query, variables: variables)
        puts resp
      end
    end
  end
end
