module ShopifyServices
    class OrderTagsGetService < ShopifyServices::GraphqlService
      attr_reader :shop
  
      def initialize(client, shop, order_id, data_query = OrderQueries::SingleOrderTags)
        @client = client
        @shop = shop
        @order_id = order_id
        @data_query = data_query
      end
  
      def call
        variables = {
          id: @order_id,
        }
        resp = @client.query(@data_query, variables: variables)
        puts "order tag response #{resp}"
        return OpenStruct.new({
                 data: resp&.data&.order,
                 errors: resp&.data&.order&.errors&.map(&:messages),
               })
      end
    end
  end
  