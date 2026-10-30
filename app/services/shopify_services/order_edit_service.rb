module ShopifyServices
    class OrderEditService < ShopifyServices::GraphqlService
      attr_reader :shop, :client
  
      def initialize(client, shop, order_id,variant_id)
        @client = client
        @shop = shop
        @order_id = order_id
        @variant_id=variant_id
      end
  
      def get_calculated_order
        query = @client.parse <<-'GRAPHQL'
        mutation($id:ID!) {
          orderEditBegin(id:$id){
             calculatedOrder{
               id
             }
           }
         }
        GRAPHQL
  
        variables = {
          id: "gid://shopify/Order/#{@order_id}"
        }
        resp = @client.query(query, variables: variables)
        resp&.data&.order_edit_begin&.calculated_order&.id
      end
  
      def add_cod_fees(calculated_order_id)
        query = @client.parse <<-'GRAPHQL'
        mutation ($id:ID!,$variantId:ID!) {
          orderEditAddVariant(id: $id, variantId: $variantId , quantity: 1){
            calculatedOrder {
              id
              addedLineItems(first:5) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
            userErrors {
              field
              message
            }
          }
        }
        GRAPHQL
  
        variables = {
          id: calculated_order_id,
          variantId: "gid://shopify/ProductVariant/#{@variant_id}"
        }
        @client.query(query, variables: variables)
      end
  
      def commit_order(calculated_order_id)
        query = @client.parse <<-'GRAPHQL'
        mutation ($id:ID!)  {
          orderEditCommit(id: $id, notifyCustomer: false, staffNote: "COD-Fees") {
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
          id: calculated_order_id,
          notifyCustomer: false
        }
        resp = @client.query(query, variables: variables)
      end
  
      def call
        calculated_order_id = get_calculated_order
        unless calculated_order_id.blank?
          resp = add_cod_fees(calculated_order_id)
          commit_order(calculated_order_id) if resp&.data&.errors&.messages&.blank?
        end
      end
    end
  end