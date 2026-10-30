# frozen_string_literal: true

module ShopifyServices
  # Copies attribution-related note_attributes from the original Shopify order onto NEW_ORDER
  # partial-payment drafts so Meta CAPI / merchants keep _fbp, _fbc, campaign JSON, etc.
  module PartialOrderAttributionCopy
    MAX_VALUE_BYTES = 5000

    WHITELIST_ATTRIBUTE_NAMES = (
      %w[
        _fbp _fbc _fbclid fbclid
        _eventSourceUrl event_source_url
        _clientUserAgent client_user_agent
        _codkPhone phone
        _codk_campaign_json _codkSessionId
      ] + CampaignAttributionHelper::ALLOWED_KEYS.map { |k| "_codk_#{k}" }
    ).freeze

    SESSION_ONLY_FOR_PARTIAL_COPY = %w[_codkSessionId].freeze

    class << self
      def meta_conversion_enabled?(shop)
        s = shop&.setting
        return true if s.nil?
        return true unless s.has_attribute?(:conversion_tracking)

        s.conversion_tracking != false
      end

      # Returns DraftOrderInput-style rows: [{ key:, value: }, ...]
      def draft_custom_attributes_from_original_order(shop, original_order_numeric_id)
        shop.init_session
        order = ShopifyAPI::Order.find(original_order_numeric_id.to_s)
        raw_attrs = order.respond_to?(:note_attributes) ? order.note_attributes : []
        return [] if raw_attrs.blank?

        allowed_names = meta_conversion_enabled?(shop) ? WHITELIST_ATTRIBUTE_NAMES : SESSION_ONLY_FOR_PARTIAL_COPY

        rows = []
        seen = {}

        raw_attrs.each do |na|
          name = (na.respond_to?(:name) ? na.name : na["name"]).to_s
          val = na.respond_to?(:value) ? na.value : na["value"]
          next if name.blank? || val.blank?
          next unless allowed_names.include?(name)
          next if seen[name]

          seen[name] = true
          s = val.to_s
          s = "#{s.byteslice(0, MAX_VALUE_BYTES - 3)}..." if s.bytesize > MAX_VALUE_BYTES
          rows << { key: name, value: s }
        end

        rows
      rescue StandardError => e
        Rails.logger.warn("[PartialOrderAttributionCopy] order=#{original_order_numeric_id} #{e.message}")
        []
      end
    end
  end
end
