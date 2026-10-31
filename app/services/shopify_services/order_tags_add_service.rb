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

        # OrderTagsGetService hands back `data: nil` whenever Shopify refused
        # the read — a rejected access token (401) above all. Reading `.id` off
        # that nil is what killed this job; there is nothing to tag without it,
        # so report and stop rather than raise.
        current = graphql_resp&.data
        if current.blank?
          Rails.logger.warn(
            "[order_tags_add] shop=#{@shop&.shopify_domain} order=#{@order_id} unreadable — tag #{@tag.inspect} not applied"
          )
          return OpenStruct.new(data: nil, errors: ['order could not be read from Shopify'])
        end

        order_data = {
          id: current.id,
          tags: (current.tags.to_s.split(",") + [@tag]).uniq.join(","),
        }
  
        resp = @client.query(query, variables: { input: order_data })
  
        return OpenStruct.new({
                 data: resp&.data&.order_update&.order&.id,
                 errors: resp&.data&.order_update&.errors&.map(&:messages),
               })
      end
    end
  end
  