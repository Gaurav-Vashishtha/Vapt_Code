# frozen_string_literal: true

module Upsells
  LINE_PROPERTY = "_codk_upsell_product"

  def self.upsell_line?(item)
    return false unless item.respond_to?(:key?)

    properties = item[:properties] || item["properties"]
    return false unless properties.respond_to?(:key?)

    (properties[LINE_PROPERTY] || properties[LINE_PROPERTY.to_sym]).to_s == "true"
  end

  def self.tag_line_item!(line_item, cart_item)
    line_item[:customAttributes] = [{ key: LINE_PROPERTY, value: "true" }] if upsell_line?(cart_item)
    line_item
  end
end
