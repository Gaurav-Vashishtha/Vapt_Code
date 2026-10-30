module ShopifyServices
  class OrderTagPostService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop, order_id, tag)
      @client = client
      @shop = shop
      @order_id = order_id
      @tag = tag
    end

    def get_order
      query = @client.parse <<-'GRAPHQL'
        query ($id:ID!){
          order(id:$id){
            id,email,phone,tags,shippingAddress{
              phone
            }
          }
        }
      GRAPHQL
      variables = {
        'id': "gid://shopify/Order/#{@order_id}"
      }
      resp = @client.query(query, variables: variables)
    end

    def get_tags(existing_order)
      new_tags = []

      unless (existing_order.data && existing_order.data.order && existing_order.data.order.tags).blank?
        existing_order.data.order.tags.each  do |tag|
          new_tags.push(tag) 
        end
      end
      new_tags.push(@tag)
    end

    def call
      existing_order = get_order
      @tags = get_tags(existing_order)

      query = @client.parse <<-'GRAPHQL'
        mutation ($input: OrderInput!) {
          orderUpdate(input: $input) {
            order {
              id
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL
      variables = {
        input: {
          id: "gid://shopify/Order/#{@order_id}",
          tags: @tags,
        }
      }
      resp = @client.query(query, variables: variables)
    end
  end
end
