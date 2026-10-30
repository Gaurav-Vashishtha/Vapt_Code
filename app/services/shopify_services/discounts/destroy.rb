module ShopifyServices
  module Discounts
    # Deletes the real Shopify discount for a Discount record. Idempotent:
    # a missing/already-deleted discount is treated as success.
    # Returns { ok:, skipped:, error: }.
    class Destroy
      def self.call(discount)
        return { ok: true, skipped: true } if discount.shopify_gid.blank?

        shop = discount.shop
        shop.init_session
        new(ShopifyAPI::GraphQL.client, discount).call
      end

      def initialize(client, discount)
        @client = client
        @d = discount
      end

      def call
        mutation_name = @d.automatic_method? ? "discountAutomaticDelete" : "discountCodeDelete"
        deleted_field = @d.automatic_method? ? "deletedAutomaticDiscountId" : "deletedCodeDiscountId"

        query = @client.parse(<<~GRAPHQL)
          mutation($id: ID!) {
            #{mutation_name}(id: $id) {
              #{deleted_field}
              userErrors { field code message }
            }
          }
        GRAPHQL

        resp = @client.query(query, variables: { id: @d.shopify_gid }).to_h

        if resp["errors"].present?
          return { ok: false, error: resp["errors"].map { |e| e["message"] }.join("; ") }
        end

        user_errors = resp.dig("data", mutation_name, "userErrors") || []
        if user_errors.any?
          messages = user_errors.map { |e| e["message"] }.join("; ")
          # Idempotent: the discount may have already been removed in Shopify.
          return { ok: true, skipped: true } if messages.match?(/not.*(found|exist)/i)

          return { ok: false, error: messages }
        end

        { ok: true }
      rescue => e
        Rails.logger.error("[Discounts::Destroy] shop=#{@d.shop&.shopify_domain} discount=#{@d.id} error=#{e.message}")
        { ok: false, error: e.message }
      end
    end
  end
end
