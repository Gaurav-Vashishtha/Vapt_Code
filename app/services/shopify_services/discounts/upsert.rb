module ShopifyServices
  module Discounts
    # Creates or updates the real native Shopify discount for a Discount record.
    # Create vs update is decided by presence of discount.shopify_gid.
    # Returns { ok:, gid:, error: }.
    class Upsert
      # Per-quadrant mutation routing.
      ROUTES = {
        ["code", :basic] => {
          input_type: "DiscountCodeBasicInput", arg: "basicCodeDiscount",
          create: "discountCodeBasicCreate", update: "discountCodeBasicUpdate", node: "codeDiscountNode"
        },
        ["automatic", :basic] => {
          input_type: "DiscountAutomaticBasicInput", arg: "automaticBasicDiscount",
          create: "discountAutomaticBasicCreate", update: "discountAutomaticBasicUpdate", node: "automaticDiscountNode"
        },
        ["code", :bxgy] => {
          input_type: "DiscountCodeBxgyInput", arg: "bxgyCodeDiscount",
          create: "discountCodeBxgyCreate", update: "discountCodeBxgyUpdate", node: "codeDiscountNode"
        },
        ["automatic", :bxgy] => {
          input_type: "DiscountAutomaticBxgyInput", arg: "automaticBxgyDiscount",
          create: "discountAutomaticBxgyCreate", update: "discountAutomaticBxgyUpdate", node: "automaticDiscountNode"
        }
      }.freeze

      def self.call(discount)
        shop = discount.shop
        shop.init_session
        new(ShopifyAPI::GraphQL.client, discount).call
      end

      def initialize(client, discount)
        @client = client
        @d = discount
      end

      def call
        route = ROUTES.fetch([@d.method, kind])
        update = @d.shopify_gid.present?
        mutation_name = update ? route[:update] : route[:create]

        input = InputBuilder.new(@d).build
        variables = { input: input }
        variables[:id] = @d.shopify_gid if update

        query = @client.parse(mutation_string(route, mutation_name, update: update))
        resp = @client.query(query, variables: variables).to_h

        if resp["errors"].present?
          return error(resp["errors"].map { |e| e["message"] }.join("; "))
        end

        payload = resp.dig("data", mutation_name) || {}
        user_errors = payload["userErrors"] || []
        return error(user_errors.map { |e| e["message"] }.join("; ")) if user_errors.any?

        gid = payload.dig(route[:node], "id")
        return error("Mutation returned no discount id") if gid.blank?

        { ok: true, gid: gid }
      rescue KeyError
        error("Unsupported discount combination: method=#{@d.method} type=#{@d.discount_type}")
      rescue => e
        Rails.logger.error("[Discounts::Upsert] shop=#{@d.shop&.shopify_domain} discount=#{@d.id} error=#{e.message}")
        error(e.message)
      end

      private

      def kind
        @d.buy_x_get_y? ? :bxgy : :basic
      end

      def mutation_string(route, mutation_name, update:)
        if update
          <<~GRAPHQL
            mutation($id: ID!, $input: #{route[:input_type]}!) {
              #{mutation_name}(id: $id, #{route[:arg]}: $input) {
                #{route[:node]} { id }
                userErrors { field code message }
              }
            }
          GRAPHQL
        else
          <<~GRAPHQL
            mutation($input: #{route[:input_type]}!) {
              #{mutation_name}(#{route[:arg]}: $input) {
                #{route[:node]} { id }
                userErrors { field code message }
              }
            }
          GRAPHQL
        end
      end

      def error(message)
        { ok: false, error: message.presence || "Unknown discount sync error" }
      end
    end
  end
end
