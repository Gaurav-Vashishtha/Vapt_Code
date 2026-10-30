# frozen_string_literal: true

module CodForm
  module Abandonment
    # ABN-3: optional Shopify draft order for an abandoned form, tagged `codking_abandoned_form`.
    # Off by default (general.abandonment.create_draft_order). The draft is informational for
    # the merchant: variant lines at catalogue prices, the contact, the recovery link in the
    # note. It is not completed and it is not the order the buyer later places.
    #
    # API 2025-07 `draftOrderCreate`; the query is validated by the GraphQL client against the
    # dumped schema at run time (F35), which is not available in this mirror.
    class DraftOrderService
      TAG = "codking_abandoned_form"

      def self.call(shop, session, recovery_url:)
        new(shop, session, recovery_url).call
      end

      def initialize(shop, session, recovery_url)
        @shop = shop
        @session = session
        @recovery_url = recovery_url
      end

      # Returns the draft order gid, or nil.
      def call
        input = build_input
        return nil if input["lineItems"].empty?

        @shop.init_session
        client = ShopifyAPI::GraphQL.client
        query = client.parse <<-'GRAPHQL'
          mutation ($input: DraftOrderInput!) {
            draftOrderCreate(input: $input) {
              draftOrder { id }
              userErrors { field message }
            }
          }
        GRAPHQL
        response = client.query(query, variables: { input: input })
        data = response&.data&.draft_order_create
        errors = Array(data&.user_errors)
        if errors.any?
          Rails.logger.warn("[codf/abandon] shop=#{@shop.id} session=#{@session.id} draft order user errors=#{errors.size}")
          return nil
        end
        data&.draft_order&.id
      end

      private

      def build_input
        quote = @session.quote_snapshot.is_a?(Hash) ? @session.quote_snapshot : {}
        contact = @session.contact.is_a?(Hash) ? @session.contact : {}
        lines = Array(quote["lines"]).filter_map do |line|
          next unless line.is_a?(Hash) && line["variant_id"].to_s.match?(/\A\d+\z/)

          { "variantId" => "gid://shopify/ProductVariant/#{line['variant_id']}", "quantity" => [line["quantity"].to_i, 1].max }
        end
        input = {
          "lineItems" => lines,
          "tags" => [TAG],
          "note" => "Abandoned COD Form. Recovery link: #{@recovery_url}",
          "customAttributes" => [{ "key" => "_codkFormSessionId", "value" => @session.public_id.to_s }]
        }
        email = contact["email"].to_s.strip
        input["email"] = email if email.include?("@")
        phone = contact["phone_e164"].to_s.strip
        input["phone"] = phone if phone.match?(/\A\+\d{8,15}\z/)
        currency = (@session.currency || quote["currency"]).to_s
        input["presentmentCurrencyCode"] = currency if currency.match?(/\A[A-Z]{3}\z/)
        input
      end
    end
  end
end
