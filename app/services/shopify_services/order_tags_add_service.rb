module ShopifyServices
    class OrderTagsAddService < ShopifyServices::GraphqlService
      def initialize(client, shop, order_id, tag)
        @client = client
        @shop = shop
        @order_id = order_id
        @tag = tag
      end
  
      def call
        query = @client.parse <<-'GRAPHQL'
        mutation ($input: OrderInput!) {
          orderUpdate(input: $input) {
            order {
              id
              tags
            }
          }
        }
      GRAPHQL
  
        graphql_resp = ShopifyServices::OrderTagsGetService.call(
          @shop, "gid://shopify/Order/#{@order_id}"
        )
  
        order_data = {
          id: graphql_resp.data.id,
          tags: (graphql_resp.data.tags.split(",") + [@tag]).uniq.join(","),
        }
  
        resp = @client.query(query, variables: { input: order_data })
  
        return OpenStruct.new({
                 data: resp&.data&.order_update&.order&.id,
                 errors: resp&.data&.order_update&.errors&.map(&:messages),
               })
      end
    end
  end
  