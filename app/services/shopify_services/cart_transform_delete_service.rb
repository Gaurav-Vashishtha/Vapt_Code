module ShopifyServices
  class CartTransformDeleteService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    def delete_cart_transform(cart_transform_id)
      query = @client.parse <<-'GRAPHQL'
        mutation($id: ID!) {
          cartTransformDelete(id: $id) {
            deletedId
            userErrors {
              field
              message
              code
            }
          }
        }
      GRAPHQL

      variables = { id: cart_transform_id }
      resp = @client.query(query, variables: variables)
      puts "resp: #{resp.inspect}"
      return resp
    end

    def call
      cart_transform_id = @shop.setting.cart_transform_id

      return true if cart_transform_id.blank?

      resp = delete_cart_transform(cart_transform_id)

      if resp&.data&.cart_transform_delete&.deleted_id.present?
        @shop.setting.update(cart_transform_id: nil)
        Rails.logger.info "Cart transform deleted successfully for shop #{@shop.shopify_domain}: #{cart_transform_id}"
        return true
      else
        error_messages = resp&.data&.cart_transform_delete&.user_errors&.map(&:message)&.join(', ')
        Rails.logger.error "Failed to delete cart transform for shop #{@shop.shopify_domain}: #{error_messages}"
        SlackNotifyJob.perform_async(
          ":rage: (#{Rails.env})\n *Unable to delete cart transform for shop #{@shop.shopify_domain}*\n Errors: #{error_messages}"
        )
        return false
      end
    end
  end
end
