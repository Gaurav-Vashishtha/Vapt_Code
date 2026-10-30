# frozen_string_literal: true

module ShopifyServices
  # Adds one variant line (optionally discounted) to an existing order by order edit.
  # Used by the COD Form one-click upsell (ARCHITECTURE.md F.6). The existing OrderEditService
  # (COD fee) is a separate class and is not touched.
  #
  #   ShopifyServices::OrderEditAddLineService.call(shop, order_id: "6123", variant_id: "44123",
  #     quantity: 1, discount: {"type" => "percentage", "value" => 20})
  #   discount: nil | {"type"=>"percentage","value"=>0..100}
  #                 | {"type"=>"fixed_amount","amount"=>"12.50","currency"=>"HUF"}   (amount PER UNIT)
  #
  # => {success: true, order_id:, total_cents:, currency:}
  #  | {success: false, code: "begin_failed"|"add_failed"|"out_of_stock"|"discount_failed"|"commit_failed"|"exception", error:}
  class OrderEditAddLineService
    STAFF_NOTE = "COD King upsell"
    DISCOUNT_DESCRIPTION = "Upsell"

    BEGIN_MUTATION = <<~GRAPHQL
      mutation ($id: ID!) {
        orderEditBegin(id: $id) {
          calculatedOrder { id }
          userErrors { field message }
        }
      }
    GRAPHQL

    ADD_VARIANT_MUTATION = <<~GRAPHQL
      mutation ($id: ID!, $variantId: ID!, $quantity: Int!, $allowDuplicates: Boolean) {
        orderEditAddVariant(id: $id, variantId: $variantId, quantity: $quantity, allowDuplicates: $allowDuplicates) {
          calculatedLineItem { id quantity }
          calculatedOrder { id }
          userErrors { field message }
        }
      }
    GRAPHQL

    ADD_DISCOUNT_MUTATION = <<~GRAPHQL
      mutation ($id: ID!, $lineItemId: ID!, $discountInput: OrderEditAppliedDiscountInput!) {
        orderEditAddLineItemDiscount(id: $id, lineItemId: $lineItemId, discount: $discountInput) {
          calculatedOrder { id }
          userErrors { field message }
        }
      }
    GRAPHQL

    COMMIT_MUTATION = <<~GRAPHQL
      mutation ($id: ID!, $staffNote: String) {
        orderEditCommit(id: $id, notifyCustomer: false, staffNote: $staffNote) {
          order {
            id
            totalPriceSet { presentmentMoney { amount currencyCode } }
          }
          userErrors { field message }
        }
      }
    GRAPHQL

    def self.call(shop, order_id:, variant_id:, quantity:, discount: nil)
      new(shop, order_id: order_id, variant_id: variant_id, quantity: quantity, discount: discount).call
    end

    def initialize(shop, order_id:, variant_id:, quantity:, discount: nil)
      @shop = shop
      @order_id = order_id.to_s
      @variant_id = variant_id.to_s
      @quantity = [quantity.to_i, 1].max
      @discount = discount
    end

    def call
      @shop.init_session
      @client = ShopifyAPI::GraphQL.client

      begun = run(BEGIN_MUTATION, { id: "gid://shopify/Order/#{@order_id}" }, "orderEditBegin")
      calculated_id = begun.dig("calculatedOrder", "id")
      return failure("begin_failed", begun) if calculated_id.blank?

      added = run(
        ADD_VARIANT_MUTATION,
        { id: calculated_id, variantId: "gid://shopify/ProductVariant/#{@variant_id}", quantity: @quantity, allowDuplicates: true },
        "orderEditAddVariant"
      )
      line_item_id = added.dig("calculatedLineItem", "id")
      if line_item_id.blank?
        code = user_error_text(added).match?(/stock|inventory|available|sold out/i) ? "out_of_stock" : "add_failed"
        return failure(code, added)
      end

      discount_input = build_discount_input
      if discount_input
        discounted = run(
          ADD_DISCOUNT_MUTATION,
          { id: calculated_id, lineItemId: line_item_id, discountInput: discount_input },
          "orderEditAddLineItemDiscount"
        )
        # Never commit an undiscounted upsell line: the buyer was promised the discounted price.
        return failure("discount_failed", discounted) if Array(discounted["userErrors"]).any? || discounted["calculatedOrder"].nil?
      end

      committed = run(COMMIT_MUTATION, { id: calculated_id, staffNote: STAFF_NOTE }, "orderEditCommit")
      order = committed["order"]
      return failure("commit_failed", committed) if order.nil? || Array(committed["userErrors"]).any?

      money = order.dig("totalPriceSet", "presentmentMoney") || {}
      {
        success: true,
        order_id: @order_id,
        total_cents: money["amount"].nil? ? nil : (BigDecimal(money["amount"].to_s) * 100).round.to_i,
        currency: money["currencyCode"]
      }
    rescue StandardError => e
      Rails.logger.error("[OrderEditAddLineService] shop_id=#{@shop.id} order_id=#{@order_id} #{e.class}")
      { success: false, code: "exception", error: e.class.name }
    end

    private

    # Returns the mutation payload as a string-keyed hash ({} when absent).
    def run(mutation, variables, root)
      response = @client.query(@client.parse(mutation), variables: variables)
      raw = response.respond_to?(:original_hash) ? response.original_hash : nil
      raw = response.to_h if raw.nil? && response.respond_to?(:to_h)
      payload = raw.is_a?(Hash) ? raw.dig("data", root) : nil
      payload.is_a?(Hash) ? payload : {}
    end

    def build_discount_input
      return nil unless @discount.is_a?(Hash)

      case @discount["type"].to_s
      when "percentage"
        value = @discount["value"].to_f
        return nil unless value.positive?

        { percentValue: [value, 100.0].min, description: DISCOUNT_DESCRIPTION }
      when "fixed_amount"
        amount = @discount["amount"].to_s
        return nil unless amount.to_f.positive?

        { fixedValue: { amount: amount, currencyCode: @discount["currency"].to_s }, description: DISCOUNT_DESCRIPTION }
      end
    end

    def user_error_text(payload)
      Array(payload["userErrors"]).map { |e| e.is_a?(Hash) ? e["message"].to_s : e.to_s }.join("; ")
    end

    def failure(code, payload)
      message = user_error_text(payload)[0, 200]
      Rails.logger.warn("[OrderEditAddLineService] shop_id=#{@shop.id} order_id=#{@order_id} code=#{code} errors=#{message}")
      { success: false, code: code, error: message.presence || code }
    end
  end
end
