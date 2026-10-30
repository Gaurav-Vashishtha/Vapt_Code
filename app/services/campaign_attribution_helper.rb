# frozen_string_literal: true

# Normalizes ad / UTM params from the COD API or Shopify order note_attributes for
# order notes, draft customAttributes, and Meta CAPI custom_data.
module CampaignAttributionHelper
  ALLOWED_KEYS = %w[
    utm_source utm_medium utm_campaign utm_content utm_term utm_id
    campaign_id ad_id fbclid gclid gbraid wbraid gad_campaignid gad_source msclkid twclid
    ttclid sccid epik
  ].freeze

  NOTE_JSON_KEY = "_codk_campaign_json"
  STOREFRONT_CART_ATTR_KEY = "codk_campaign_attribution"

  class << self
    def normalize(raw)
      return {} if raw.blank?
      h = if raw.respond_to?(:to_unsafe_h)
            raw.to_unsafe_h
          elsif raw.is_a?(Hash)
            raw
          else
            {}
          end
      out = {}
      h.each do |k, v|
        ks = k.to_s
        next unless ALLOWED_KEYS.include?(ks)

        s = v.to_s.strip
        next if s.blank?

        out[ks] = s.byteslice(0, 500)
      end
      out
    end

    # Reads attribution saved on the order (draft customAttributes → note_attributes).
    def from_note_attributes(order)
      return {} if order.blank?

      attrs = order.try(:note_attributes)
      return {} if attrs.blank?

      [NOTE_JSON_KEY, STOREFRONT_CART_ATTR_KEY].each do |key|
        blob = find_note_attr_value(attrs, key)
        next if blob.blank?
        begin
          parsed = JSON.parse(blob)
          return normalize(parsed) if parsed.is_a?(Hash) && parsed.any? { |k, _| ALLOWED_KEYS.include?(k.to_s) }
        rescue JSON::ParserError
          next
        end
      end

      out = {}
      ALLOWED_KEYS.each do |key|
        val = find_note_attr_value(attrs, "_codk_#{key}")
        out[key] = val if val.present?
      end
      normalize(out)
    end

    def find_note_attr_value(attrs, name)
      attrs.each do |na|
        n = na.respond_to?(:name) ? na.name : na["name"]
        next unless n.to_s == name

        val = na.respond_to?(:value) ? na.value : na["value"]
        s = val.to_s.strip
        return s if s.present?
      end
      nil
    end

    # Shopify DraftOrderInput customAttributes — single JSON blob (fits typical payloads).
    def shopify_custom_attributes_blob(hash)
      h = normalize(hash)
      return [] if h.blank?

      json = h.to_json
      json = "#{json.byteslice(0, 4497)}..." if json.bytesize > 4500
      [{ key: NOTE_JSON_KEY, value: json }]
    end

    # Human-readable lines for order note (merchant-visible).
    def format_note_lines(hash)
      h = normalize(hash)
      return nil if h.blank?

      lines = ["Campaign attribution:"]
      ALLOWED_KEYS.each do |k|
        next if h[k].blank?

        lines << "#{k}=#{h[k]}"
      end
      lines.join("\n").byteslice(0, 3500)
    end

    def apply_to_meta_custom_data!(data, raw_campaign)
      campaign = normalize(raw_campaign)
      return data if campaign.blank?

      campaign.each do |key, val|
        next if val.blank?

        data[key.to_sym] = val.to_s.byteslice(0, 500)
      end
      data
    end
  end
end
