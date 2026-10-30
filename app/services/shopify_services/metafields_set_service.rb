# frozen_string_literal: true

module ShopifyServices
  # Generic service to set metafields via Shopify GraphQL metafieldsSet mutation.
  #
  # Usage:
  #   metafields = [
  #     {
  #       ownerId: "gid://shopify/PaymentCustomization/123",
  #       namespace: "payment-customization",
  #       key: "function-configuration",
  #       value: { ... }.to_json,
  #       type: "json"
  #     }
  #   ]
  #   ShopifyServices::MetafieldsSetService.call(Shop.last, metafields)
  #
  # Or with existing client (e.g. from another service):
  #   ShopifyServices::MetafieldsSetService.new(client, shop).call(metafields)
  class MetafieldsSetService < ShopifyServices::GraphqlService
    attr_reader :shop, :client

    # @param shop [Shop] Shop model (when using .call)
    # @param metafields [Array<Hash>] Array of MetafieldsSetInput (ownerId, namespace, key, value, type, etc.)
    # @return [Hash, nil] Response data with metafields and userErrors, or nil on failure
    def self.call(shop, metafields)
      shop.init_session
      client = ShopifyAPI::GraphQL.client
      new(client, shop).call(metafields)
    end

    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    # @param metafields [Array<Hash>] Array of MetafieldsSetInput
    # @return [Hash, nil] { metafields: [...], user_errors: [...] } or nil if no response
    def call(metafields)
      Rails.logger.info "[MetafieldsSetService] shop_id=#{@shop.id} metafields_count=#{metafields.size}"
      resp = set_metafields(metafields)
      data = resp&.data&.metafields_set

      unless data
        Rails.logger.warn "[MetafieldsSetService] shop_id=#{@shop.id} no data in response"
        return nil
      end

      result = {
        metafields: data.metafields&.map { |m| metafield_to_hash(m) } || [],
        user_errors: data.user_errors || []
      }
      Rails.logger.info "[MetafieldsSetService] shop_id=#{@shop.id} metafields_set=#{result[:metafields].size} user_errors=#{result[:user_errors].inspect}"
      result
    end

    # Raw GraphQL response (for callers that need full response or userErrors)
    # @param metafields [Array<Hash>]
    # @return [Object] GraphQL response
    def set_metafields(metafields)
      query = @client.parse <<-'GRAPHQL'
        mutation ($metafields: [MetafieldsSetInput!]!) {
          metafieldsSet(metafields: $metafields) {
            metafields {
              id
              namespace
              key
              value
              type
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      variables = { metafields: metafields }
      @client.query(query, variables: variables)
    end

    private

    def metafield_to_hash(metafield)
      return {} unless metafield

      {
        id: metafield.id,
        namespace: metafield.namespace,
        key: metafield.key,
        value: metafield.value,
        type: metafield.type
      }
    end
  end
end
