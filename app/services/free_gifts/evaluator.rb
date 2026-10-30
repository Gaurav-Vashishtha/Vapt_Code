# frozen_string_literal: true

module FreeGifts
  class Evaluator
    Line = Struct.new(:product_id, :variant_id, :quantity, :line_total, keyword_init: true)

    def initialize(config)
      @rules = config["enabled"] ? config["rules"].select { |rule| rule["enabled"] && rule["gift_variant_id"] } : []
      @stacking = config["stacking"]
    end

    def matched_rules(lines)
      subtotal = lines.sum(0.to_d) { |line| line.line_total.to_d }
      item_count = lines.sum(&:quantity)
      matched = @rules.select { |rule| matches?(rule, lines, subtotal, item_count) }
      matched = matched.first(1) unless @stacking
      matched.uniq { |rule| rule["gift_variant_id"] }
    end

    private

    def matches?(rule, lines, subtotal, item_count)
      case rule["trigger"]
      when "cart_range"
        subtotal >= rule["min_amount"].to_d && (rule["max_amount"].nil? || subtotal < rule["max_amount"].to_d)
      when "cart_items" then item_count >= rule["min_items"].to_i
      when "product" then product_match?(rule, lines)
      when "collection"
        lines.select { |line| rule["collection_product_ids"].include?(line.product_id) }.sum(&:quantity) >= rule["min_quantity"].to_i
      else false
      end
    end

    def product_match?(rule, lines)
      cart_ids = lines.map(&:product_id)
      hits = rule["product_ids"].map { |id| cart_ids.include?(id) }
      return false if hits.empty?

      rule["match"] == "all" ? hits.all? : hits.any?
    end
  end
end
