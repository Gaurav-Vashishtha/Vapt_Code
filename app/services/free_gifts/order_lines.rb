# frozen_string_literal: true

module FreeGifts
  class OrderLines
    DISCOUNT_TITLE = "Free gift"

    def initialize(shop, items)
      @shop = shop
      @items = Array(items)
      @config = FreeGifts.config_for(shop)
    end

    def regular_items
      @items.reject { |item| FreeGifts.gift_line?(item) }
    end

    def gift_line_items
      gifts = @items.select { |item| FreeGifts.gift_line?(item) }
      return [] if gifts.empty? || !@config["enabled"]

      by_variant = Evaluator.new(@config).matched_rules(evaluation_lines).index_by { |rule| rule["gift_variant_id"] }
      gifts.filter_map do |item|
        rule = by_variant.delete(variant_id(item))
        next unless rule

        {
          variantId: "gid://shopify/ProductVariant/#{rule['gift_variant_id']}",
          quantity: [(item[:quantity] || item["quantity"]).to_i, 1].max.clamp(1, rule["gift_quantity"]),
          customAttributes: [{ key: LINE_PROPERTY, value: rule["id"] }],
          appliedDiscount: { valueType: "PERCENTAGE", value: 100.0, title: DISCOUNT_TITLE, description: DISCOUNT_TITLE }
        }
      end
    rescue StandardError => e
      Rails.logger.warn("[FreeGifts] gift lines dropped shop_id=#{@shop&.id} #{e.class}: #{e.message.to_s[0, 200]}")
      []
    end

    private

    def variant_id(item)
      FreeGifts.numeric_id(item[:variant_id] || item["variant_id"] || item[:id] || item["id"])
    end

    def evaluation_lines
      items = regular_items
      catalog = Catalog.variants(@shop, items.filter_map { |item| variant_id(item) })
      items.filter_map do |item|
        info = catalog[variant_id(item)]
        next unless info

        quantity = (item[:quantity] || item["quantity"]).to_i
        discount_cents = Array(item[:line_level_discount_allocations] || item["line_level_discount_allocations"])
                         .sum { |d| (d[:amount] || d["amount"]).to_i }
        Evaluator::Line.new(
          product_id: info[:product_id],
          variant_id: variant_id(item),
          quantity: quantity,
          line_total: [info[:price] * quantity - discount_cents.to_d / 100, 0.to_d].max
        )
      end
    end
  end
end
