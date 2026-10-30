module ShopifyServices
  module Discounts
    # Pure Ruby: maps a Discount record to the GraphQL input hash for the
    # matching native Shopify discount mutation (no Shopify Functions).
    #
    # Routes by (method, discount_type):
    #   code      + amount_off/percentage -> DiscountCodeBasicInput
    #   automatic + amount_off/percentage -> DiscountAutomaticBasicInput
    #   code      + buy_x_get_y           -> DiscountCodeBxgyInput
    #   automatic + buy_x_get_y           -> DiscountAutomaticBxgyInput
    #
    # bxgy_config shape (JSON on the Discount record):
    #   {
    #     "buys_type":  "quantity" | "amount",
    #     "buys_value": "3",
    #     "buys_items": "all" | "products" | "collections",
    #     "buys_product_gids":    [..], "buys_collection_gids": [..],
    #     "gets_qty":          "1",
    #     "gets_effect_value": 100   # percentage off the "get Y" items (100 = free)
    #   }
    # The "get Y" item set is the discount's own applies_to / product_gids / collection_gids.
    class InputBuilder
      def initialize(discount)
        @d = discount
      end

      def build
        @d.buy_x_get_y? ? build_bxgy : build_basic
      end

      private

      def build_basic
        input = {
          title: @d.title,
          startsAt: starts_at,
          customerGets: { value: basic_value, items: gets_items },
          combinesWith: combines_with
        }
        input[:endsAt] = ends_at if @d.ends_at.present?
        if (req = minimum_requirement)
          input[:minimumRequirement] = req
        end
        apply_code_only_fields!(input, uses_per_order: false)
        input
      end

      def build_bxgy
        cfg = (@d.bxgy_config || {}).with_indifferent_access
        input = {
          title: @d.title,
          startsAt: starts_at,
          customerBuys: { value: buys_value(cfg), items: buys_items(cfg) },
          customerGets: {
            value: { discountOnQuantity: { quantity: int_str(cfg[:gets_qty], 1), effect: gets_effect(cfg) } },
            items: gets_items
          },
          combinesWith: combines_with
        }
        input[:endsAt] = ends_at if @d.ends_at.present?
        apply_code_only_fields!(input, uses_per_order: true)
        input
      end

      # Fields that only exist on the *code* input types.
      def apply_code_only_fields!(input, uses_per_order:)
        return unless @d.code_method?

        input[:code] = @d.code
        input[:customerSelection] = { all: true }
        input[:appliesOncePerCustomer] = @d.once_per_customer
        if @d.usage_limit.present?
          uses_per_order ? input[:usesPerOrderLimit] = @d.usage_limit : input[:usageLimit] = @d.usage_limit
        end
      end

      def basic_value
        if @d.discount_type == "amount_off"
          { discountAmount: { amount: money(@d.value), appliesOnEachItem: false } }
        else
          { percentage: normalize_percentage(@d.value.to_f) }
        end
      end

      # BXGY "get Y" effect. v1 supports percentage off only (100 = free).
      def gets_effect(cfg)
        { percentage: normalize_percentage((cfg[:gets_effect_value] || 100).to_f) }
      end

      def buys_value(cfg)
        if (cfg[:buys_type] || "quantity").to_s == "amount"
          { amount: money(cfg[:buys_value]) }
        else
          { quantity: int_str(cfg[:buys_value], 1) }
        end
      end

      def buys_items(cfg)
        items_for(cfg[:buys_items] || "all", Array(cfg[:buys_product_gids]), Array(cfg[:buys_collection_gids]))
      end

      def gets_items
        items_for(@d.applies_to, @d.product_gids_array, @d.collection_gids_array)
      end

      def items_for(scope, products, collections)
        case scope.to_s
        when "products"    then { products: { productsToAdd: products.map(&:to_s).reject(&:blank?) } }
        when "collections" then { collections: { add: collections.map(&:to_s).reject(&:blank?) } }
        else { all: true }
        end
      end

      def minimum_requirement
        return nil if @d.minimum_requirement_type.blank? || @d.minimum_requirement_value.blank?

        if @d.minimum_requirement_type == "subtotal"
          { subtotal: { greaterThanOrEqualToSubtotal: money(@d.minimum_requirement_value) } }
        else
          { quantity: { greaterThanOrEqualToQuantity: int_str(@d.minimum_requirement_value, 1) } }
        end
      end

      def combines_with
        {
          orderDiscounts: !!@d.combines_with_order,
          productDiscounts: !!@d.combines_with_product,
          shippingDiscounts: !!@d.combines_with_shipping
        }
      end

      def starts_at
        (@d.starts_at || Time.current).utc.iso8601
      end

      def ends_at
        @d.ends_at&.utc&.iso8601
      end

      # Percentages are 0-1 fractions in the Admin API. Accept either "10" or "0.1".
      def normalize_percentage(value)
        return 0.0 if value.negative?

        value > 1.0 ? (value / 100.0) : value
      end

      def money(value)
        value.to_f.round(2).to_s
      end

      def int_str(value, default)
        v = value.to_i
        v.positive? ? v.to_s : default.to_s
      end
    end
  end
end
