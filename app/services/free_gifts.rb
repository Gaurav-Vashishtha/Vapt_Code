# frozen_string_literal: true

module FreeGifts
  LINE_PROPERTY = "_codk_free_gift"
  FUNCTION_METAFIELD_NAMESPACE = "$app"
  FUNCTION_METAFIELD_KEY = "free-gifts"

  module_function

  def numeric_id(value)
    digits = value.to_s[%r{(\d+)\z}, 1]
    digits && digits.to_i.positive? ? digits.to_i : nil
  end

  def line_properties(item)
    return {} unless item.respond_to?(:key?)

    properties = item[:properties] || item["properties"]
    properties = properties.to_unsafe_h if properties.respond_to?(:to_unsafe_h)
    case properties
    when Hash then properties.transform_keys(&:to_s)
    when Array then properties.each_with_object({}) { |p, h| h[(p["name"] || p[:name]).to_s] = (p["value"] || p[:value]) }
    else {}
    end
  end

  def gift_line?(item)
    line_properties(item)[LINE_PROPERTY].present?
  end

  def config_for(shop)
    Config.sanitize(shop&.additional_setting&.free_gift_config)
  end

  def enabled_for?(shop)
    config = config_for(shop)
    config["enabled"] && config["rules"].any? { |rule| rule["enabled"] }
  end

  def storefront_payload(shop)
    config = config_for(shop)
    rules = config["rules"].select { |rule| rule["enabled"] }
    return nil unless config["enabled"] && rules.any?

    config.merge("rules" => rules.map { |rule| storefront_rule(rule) })
  end

  def storefront_rule(rule)
    rule.slice(
      "id", "trigger", "min_amount", "max_amount", "min_items", "product_ids", "match",
      "collection_product_ids", "min_quantity", "gift_product_id", "gift_variant_id", "gift_quantity", "gift"
    )
  end

  def function_payload(shop)
    config = config_for(shop)
    rules = config["enabled"] ? config["rules"].select { |rule| rule["enabled"] } : []
    {
      "stack" => config["stacking"],
      "rules" => rules.map do |rule|
        {
          "id" => rule["id"],
          "t" => rule["trigger"],
          "min" => rule["min_amount"],
          "max" => rule["max_amount"],
          "items" => rule["min_items"],
          "p" => rule["product_ids"],
          "m" => rule["match"],
          "c" => rule["collection_product_ids"],
          "q" => rule["min_quantity"],
          "gv" => rule["gift_variant_id"],
          "gq" => rule["gift_quantity"]
        }.compact
      end
    }
  end
end
