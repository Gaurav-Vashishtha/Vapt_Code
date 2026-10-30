# frozen_string_literal: true

require "json"

module CodForm
  # App-embed status for the Setup screen (D.15 `setup.embed`, F.1).
  #
  # Reads `config/settings_data.json` of the main theme through the existing
  # ShopifyServices::ShopifyAssetService, but — unlike its `is_cod_king_block_enabled?`, which
  # matches any block of the app — tells the two embeds apart by block type:
  #   …/blocks/cod-form-embed/<uid>  → the new COD Form embed   ("enabled")
  #   …/blocks/app-embed/<uid>       → the legacy "COD King OTP Block" ("legacy_enabled")
  #
  # `parse` is pure and unit-tested without Rails: ruby test/services/cod_form/embed_status_service_test.rb
  class EmbedStatusService
    NEW_BLOCK = %r{/blocks/cod-form-embed(/|\z)}.freeze
    LEGACY_BLOCK = %r{/blocks/app-embed(/|\z)}.freeze
    LEGACY_APP_MARK = "cod-king"
    EMBED_HANDLE = "cod-form-embed"
    CACHE_TTL = 300 # seconds

    class << self
      # => {"enabled" => bool|nil, "legacy_enabled" => bool|nil, "theme_editor_url" => String,
      #     "legacy_theme_editor_url" => String, "checked_at" => ISO 8601|nil}
      # `enabled` / `legacy_enabled` are nil when the theme could not be read (the UI then shows
      # "unknown" instead of a wrong "off").
      def call(shop, refresh: false)
        status = refresh ? nil : CodForm::Cache.store.read(cache_key(shop))
        unless status.is_a?(Hash)
          status = fetch(shop)
          # An unreadable theme is not cached, so the next request tries again.
          if status["checked_at"]
            CodForm::Cache.store.write(cache_key(shop), status, expires_in: CACHE_TTL)
          elsif refresh
            CodForm::Cache.store.delete(cache_key(shop))
          end
        end
        status.merge(urls(shop))
      end

      def cache_key(shop)
        "codf:embed:#{shop.id}"
      end

      # settings_data: the JSON string (or parsed Hash) of config/settings_data.json.
      # => {"enabled" => bool, "legacy_enabled" => bool}
      def parse(settings_data, extension_uuid: nil)
        data = settings_data.is_a?(String) ? JSON.parse(settings_data) : settings_data
        current = data.is_a?(Hash) ? data["current"] : nil
        # `current` is a preset name when the theme was never customised.
        current = data.dig("presets", current) if current.is_a?(String)
        blocks = current.is_a?(Hash) && current["blocks"].is_a?(Hash) ? current["blocks"].values : []

        enabled = false
        legacy = false
        blocks.each do |block|
          next unless block.is_a?(Hash) && block["disabled"] != true

          type = block["type"].to_s
          if type.match?(NEW_BLOCK)
            enabled = true if extension_uuid.to_s.empty? || type.include?(extension_uuid.to_s) || type.include?(LEGACY_APP_MARK)
          elsif type.match?(LEGACY_BLOCK) && type.include?(LEGACY_APP_MARK)
            legacy = true
          end
        end
        { "enabled" => enabled, "legacy_enabled" => legacy }
      rescue JSON::ParserError
        { "enabled" => false, "legacy_enabled" => false }
      end

      def theme_editor_url(shopify_domain, extension_uuid)
        base = "https://#{shopify_domain}/admin/themes/current/editor?context=apps"
        extension_uuid.to_s.empty? ? base : "#{base}&template=product&activateAppId=#{extension_uuid}/#{EMBED_HANDLE}"
      end

      private

      def urls(shop)
        {
          # Shopify's documented deep link is activateAppId={api_key}/{handle}: it opens App embeds
          # with the COD Form embed switched on and in focus (the extension id is the older form).
          "theme_editor_url" => theme_editor_url(shop.shopify_domain, ENV["SHOPIFY_API_KEY"].presence || ENV["COD_FORM_EXTENSION_UUID"]),
          "legacy_theme_editor_url" => theme_editor_url(shop.shopify_domain, nil)
        }
      end

      def fetch(shop)
        asset = ShopifyServices::ShopifyAssetService.new(shop).fetch_asset
        value = asset.is_a?(Hash) ? asset.dig("asset", "value") : nil
        return unknown if value.nil?

        parse(value, extension_uuid: ENV["COD_FORM_EXTENSION_UUID"]).merge("checked_at" => Time.current.utc.iso8601)
      rescue StandardError => e
        Rails.logger.warn("[CodForm::EmbedStatusService] shop_id=#{shop.id} #{e.class}")
        unknown
      end

      def unknown
        { "enabled" => nil, "legacy_enabled" => nil, "checked_at" => nil }
      end
    end
  end
end
