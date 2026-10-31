# frozen_string_literal: true

module Upsells
  module Config
    MAX_ITEMS = [3, 5, 7, 8, 9, 10].freeze
    DEFAULT_MAX_ITEMS = 5
    ITEM_TYPES = %w[product collection].freeze
    MAX_CONFIG_ITEMS = 50
    MAX_VARIANT_IDS = 100

    module_function

    def sanitize(raw)
      raw = raw.to_h if raw.respond_to?(:to_h) && !raw.is_a?(Hash)
      return nil unless raw.is_a?(Hash)

      raw = raw.transform_keys(&:to_s)
      {
        "enabled" => raw["enabled"] == true || raw["enabled"].to_s == "true",
        "max_items" => MAX_ITEMS.include?(raw["max_items"].to_i) ? raw["max_items"].to_i : DEFAULT_MAX_ITEMS,
        "show_quantity_selector" => raw["show_quantity_selector"] == true || raw["show_quantity_selector"].to_s == "true",
        "vertical_layout" => raw["vertical_layout"] == true || raw["vertical_layout"].to_s == "true",
        "items" => sanitize_items(raw["items"])
      }
    end

    def sanitize_items(items)
      list = items.is_a?(Hash) ? items.values : Array(items)
      seen = {}
      list.filter_map do |item|
        item = item.to_h if item.respond_to?(:to_h) && !item.is_a?(Hash)
        next unless item.is_a?(Hash)

        item = item.transform_keys(&:to_s)
        type = item["type"].to_s
        id = numeric_id(item["shopify_id"])
        next if !ITEM_TYPES.include?(type) || id.nil? || seen[[type, id]]

        seen[[type, id]] = true
        variant_ids = type == "product" ? Array(item["variant_ids"]).filter_map { |v| numeric_id(v) }.uniq.first(MAX_VARIANT_IDS) : []
        auto_add = type == "product" && (item["auto_add"] == true || item["auto_add"].to_s == "true")
        { "type" => type, "shopify_id" => id, "variant_ids" => variant_ids, "auto_add" => auto_add, "position" => item["position"].to_i }
      end.sort_by { |item| item["position"] }
         .first(MAX_CONFIG_ITEMS)
         .each_with_index.map { |item, index| item.merge("position" => index) }
    end

    def numeric_id(value)
      digits = value.to_s[%r{(\d+)\z}, 1]
      digits && digits.to_i.positive? ? digits.to_i : nil
    end
  end
end
