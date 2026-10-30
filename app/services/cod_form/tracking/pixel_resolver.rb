# frozen_string_literal: true

module CodForm
  module Tracking
    # ARCHITECTURE.md I.3 / B.10 / C.6.
    #
    #   PixelResolver.for(shop, product_ids:, collection_ids:)
    #     -> pixels for the STOREFRONT (session response): no token, browser pixels only.
    #   PixelResolver.server_pixels(shop, product_ids:, collection_ids:)
    #     -> pixels for the server dispatch, WITH access_token. Never serialise or log these.
    #
    # Both apply the gates (first_pixel, extra_pixels, pixels_p3), the limit of 5 per platform,
    # the product targeting (TRK-8), and add the implicit Meta pixel from Setting (B.10).
    # `select`, `storefront` and `targeting_match?` are pure (plain hashes in and out).
    class PixelResolver
      MAX_PER_PLATFORM = 5
      P3_PLATFORMS = %w[snapchat pinterest].freeze
      STOREFRONT_CONFIG_KEYS = %w[browser purchase_event events conversion_label tiktok_event].freeze
      DEFAULT_EVENTS = { "form_open" => true, "add_payment_info" => false, "purchase" => true }.freeze

      class << self
        def for(shop, product_ids: [], collection_ids: [])
          resolve(shop, product_ids: product_ids, collection_ids: collection_ids)
            .select { |pixel| browser?(pixel) }
            .map { |pixel| storefront(pixel) }
        end

        def server_pixels(shop, product_ids: [], collection_ids: [])
          resolve(shop, product_ids: product_ids, collection_ids: collection_ids)
            .select { |pixel| pixel["config"]["server"] != false }
        end

        # ---- pure -----------------------------------------------------------------------

        # pixels: [{"id","platform","pixel_id","access_token","config","targeting","position"}]
        #         (enabled rows only, any order)
        # implicit_meta: {"pixel_id","access_token","test_event_code"} or nil
        # gates: {"first_pixel" => {"allowed" => true}, ...} (CodForm::Gates.for)
        def select(pixels:, implicit_meta: nil, gates: {}, product_ids: [], collection_ids: [])
          ordered = Array(pixels).select { |p| p.is_a?(Hash) }
                                 .sort_by { |p| [p["position"].to_i, p["id"].to_i] }
                                 .map { |p| normalize(p) }

          if implicit_meta.is_a?(Hash) && !implicit_meta["pixel_id"].to_s.strip.empty?
            implicit_id = implicit_meta["pixel_id"].to_s.strip
            already = ordered.any? { |p| p["platform"] == "meta" && p["pixel_id"] == implicit_id }
            ordered.unshift(implicit_pixel(implicit_meta)) unless already
          end

          seen = Hash.new(0)
          allowed = ordered.select do |pixel|
            platform = pixel["platform"]
            index = seen[platform]
            seen[platform] += 1
            next false if index >= MAX_PER_PLATFORM
            next false unless gate?(gates, index.zero? ? "first_pixel" : "extra_pixels")
            next false if needs_p3?(pixel) && !gate?(gates, "pixels_p3")

            true
          end

          allowed.select { |pixel| targeting_match?(pixel["targeting"], product_ids, collection_ids) }
        end

        # Meta pixels that reach the Conversions API fire no browser events.
        def browser?(pixel)
          return false if pixel["config"]["browser"] == false

          !(pixel["platform"] == "meta" && server?(pixel))
        end

        def server?(pixel)
          pixel["config"]["server"] != false && !pixel["access_token"].to_s.empty?
        end

        # C.6 storefront representation: no token, no server-only config.
        def storefront(pixel)
          config = pixel["config"].is_a?(Hash) ? pixel["config"] : {}
          {
            "platform" => pixel["platform"],
            "pixel_id" => pixel["pixel_id"],
            "config" => config.select { |key, _| STOREFRONT_CONFIG_KEYS.include?(key) },
            "targeting" => pixel["targeting"]
          }
        end

        def targeting_match?(targeting, product_ids, collection_ids)
          targeting = targeting.is_a?(Hash) ? targeting : {}
          return true unless targeting["scope"].to_s == "selected"

          products = Array(targeting["product_ids"]).map(&:to_s)
          collections = Array(targeting["collection_ids"]).map(&:to_s)
          !(products & Array(product_ids).map(&:to_s)).empty? ||
            !(collections & Array(collection_ids).map(&:to_s)).empty?
        end

        private

        def resolve(shop, product_ids:, collection_ids:)
          rows = CodForm::TrackingPixel.where(shop_id: shop.id, enabled: true).order(:position, :id).map do |row|
            {
              "id" => row.id, "platform" => row.platform, "pixel_id" => row.pixel_id,
              "access_token" => row.access_token, "config" => row.config, "targeting" => row.targeting,
              "position" => row.position
            }
          end
          select(
            pixels: rows,
            implicit_meta: implicit_meta_for(shop),
            gates: CodForm::Gates.for(shop),
            product_ids: product_ids,
            collection_ids: collection_ids
          )
        end

        # The single Meta pixel on Setting keeps working unchanged (B.10).
        def implicit_meta_for(shop)
          setting = shop.setting
          return nil if setting.nil?
          return nil unless NetworkServices::MetaConversionService.meta_conversion_enabled?(setting)

          pixel_id = setting.pixel_id.to_s.encode(Encoding::ASCII, invalid: :replace, undef: :replace, replace: "").strip
          return nil if pixel_id.empty?

          {
            "pixel_id" => pixel_id,
            "access_token" => setting.pixel_token.to_s.strip,
            "test_event_code" => setting.pixel_test_event_id.to_s.strip
          }
        end

        def normalize(pixel)
          config = pixel["config"].is_a?(Hash) ? pixel["config"].dup : {}
          config["browser"] = true unless config.key?("browser")
          config["server"] = true unless config.key?("server")
          config["purchase_event"] = "purchase" unless %w[purchase lead].include?(config["purchase_event"])
          config["events"] = DEFAULT_EVENTS.merge(config["events"].is_a?(Hash) ? config["events"] : {})
          targeting = pixel["targeting"].is_a?(Hash) ? pixel["targeting"] : {}
          {
            "id" => pixel["id"],
            "platform" => pixel["platform"].to_s,
            "pixel_id" => pixel["pixel_id"].to_s.strip,
            "access_token" => pixel["access_token"].to_s.strip,
            "config" => config,
            "targeting" => {
              "scope" => targeting["scope"].to_s == "selected" ? "selected" : "all",
              "product_ids" => Array(targeting["product_ids"]).map(&:to_s),
              "collection_ids" => Array(targeting["collection_ids"]).map(&:to_s)
            },
            "implicit" => pixel["implicit"] == true
          }
        end

        def implicit_pixel(meta)
          token = meta["access_token"].to_s.strip
          normalize(
            "id" => nil, "platform" => "meta", "pixel_id" => meta["pixel_id"].to_s.strip,
            "access_token" => token, "implicit" => true,
            "config" => {
              "browser" => true, "server" => !token.empty?, "purchase_event" => "purchase",
              "test_event_code" => meta["test_event_code"].to_s
            },
            "targeting" => { "scope" => "all" }
          )
        end

        def needs_p3?(pixel)
          P3_PLATFORMS.include?(pixel["platform"]) || pixel["targeting"]["scope"] == "selected"
        end

        def gate?(gates, key)
          entry = gates.is_a?(Hash) ? gates[key] : nil
          entry.is_a?(Hash) && entry["allowed"] == true
        end
      end
    end
  end
end
