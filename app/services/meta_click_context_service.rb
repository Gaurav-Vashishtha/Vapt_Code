# frozen_string_literal: true

# Reads Meta CAPI fields from Shopify order note_attributes (set from cart: _fbp, _fbc, …).
# Used by PartialOrderEditJob for remaining_balance events. No server-side table.
class MetaClickContextService
  def self.meta_conversion_enabled_for_shop?(shop)
    s = shop&.setting
    return true if s.nil?
    return true unless s.has_attribute?(:conversion_tracking)

    s.conversion_tracking != false
  end

  # Merges note attributes: +order+ wins over +fallback_order+ (e.g. new split order vs original).
  # +shop+ is reserved for a stable call shape (unused).
  def self.fetch_for_capi(shop, order: nil, fallback_order: nil)
    return [{}, {}] unless meta_conversion_enabled_for_shop?(shop)

    _ = shop
    f_meta, f_ctx = meta_from_shopify_order_note_attributes(fallback_order)
    o_meta, o_ctx = meta_from_shopify_order_note_attributes(order)
    meta_click_data = (f_meta || {}).merge(o_meta || {})
    client_context = (f_ctx || {}).merge(o_ctx || {})
    [meta_click_data, client_context]
  end

  def self.meta_from_shopify_order_note_attributes(order)
    return [{}, {}] if order.blank?

    attrs = order.try(:note_attributes)
    return [{}, {}] if attrs.blank?

    h = {}
    attrs.each do |na|
      name = na.respond_to?(:name) ? na.name : na["name"]
      val = na.respond_to?(:value) ? na.value : na["value"]
      s = val.to_s.strip
      next if s.blank?

      case name.to_s
      when "_fbp" then h["fbp"] = s
      when "_fbc" then h["fbc"] = s
      when "_fbclid", "fbclid" then h["fbclid"] = s
      when "_eventSourceUrl", "event_source_url" then h["event_source_url"] = s
      when "_clientUserAgent", "client_user_agent" then h["client_user_agent"] = s
      when "_codkPhone", "phone" then h["phone"] = s
      end
    end

    meta_click_data = h.slice("fbp", "fbc", "fbclid", "event_source_url", "client_user_agent", "phone").compact
    client_context = {
      "event_source_url" => meta_click_data["event_source_url"],
      "client_user_agent" => meta_click_data["client_user_agent"],
    }.compact
    [meta_click_data, client_context]
  end

  def self.codk_session_id_from_shopify_order(order)
    return nil unless order

    attrs = order.try(:note_attributes)
    return nil if attrs.blank?

    attrs.each do |na|
      name = na.respond_to?(:name) ? na.name : na["name"]
      next unless name.to_s == "_codkSessionId"

      val = na.respond_to?(:value) ? na.value : na["value"]
      s = val.to_s.strip
      return s if s.present?
    end
    nil
  end
end
