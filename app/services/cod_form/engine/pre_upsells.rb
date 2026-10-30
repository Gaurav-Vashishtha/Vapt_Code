# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "money"
  require_relative "offers"
end

module CodForm
  module Engine
    # Pre-purchase upsells (offer_type "pre_upsell"): rules shown in a popup after the buyer taps
    # "Complete order" and before the order is created.
    #
    #   targeting       {"scope" => "all" | "selected", "product_ids", "collection_ids"}: "If the cart has"
    #   config["match"] "any" (one chosen product / collection is in the cart) | "all" (every one is)
    #   config["min_cart_cents"] / ["max_cart_cents"]  optional merchandise range (before this offer)
    #   config["source"] "products" | "collection": what is offered
    #   config["candidates"] [{"product_id", "variant_ids"}] kept by CodForm::PreUpsellCatalog (the
    #                    chosen products, or the products of the chosen collection, in order)
    #   config["max_products"] 1..6, config["discount_type"] none | percentage | fixed_amount | fixed_price
    #   config["display"] "popup" (after Complete order) | "inline" (a card in the form at config["position"])
    #
    # Only one rule is shown per checkout: the first matching one by priority. Its products that are
    # already in the cart or out of stock are skipped. Prices always come from the catalog here.
    class PreUpsells
      TYPE = "pre_upsell"
      MAX_PRODUCTS = 6
      MAX_VARIANTS = 10
      MAX_QUANTITY = 10
      DISCOUNT_TYPES = %w[none percentage fixed_amount fixed_price].freeze

      class << self
        # The rules whose "If the cart has" holds for these product lines (cart value not checked).
        def for_cart(offers:, lines:)
          Offers.sorted(offers).select do |offer|
            Offers.active?(offer) && offer["offer_type"].to_s == TYPE && cart_matches?(offer, lines)
          end
        end

        # The rule shown for this cart: the first by priority whose cart condition and cart value
        # range hold and that still has something to offer. nil when none.
        def match(offers:, lines:, merchandise_cents:, catalog:)
          for_cart(offers: offers, lines: lines).find do |offer|
            in_range?(offer, merchandise_cents) && products(offer: offer, catalog: catalog, lines: lines).any?
          end
        end

        def cart_matches?(offer, lines)
          targeting = hash(offer["targeting"])
          return true if targeting["scope"].to_s != "selected"

          lines = product_lines(lines)
          product_ids = strings(targeting["product_ids"])
          collection_ids = strings(targeting["collection_ids"])
          in_cart = lines.map { |line| line["product_id"].to_s }
          cart_collections = lines.flat_map { |line| strings(line["collection_ids"]) }
          if hash(offer["config"])["match"].to_s == "all"
            (product_ids - in_cart).empty? && (collection_ids - cart_collections).empty? &&
              !(product_ids.empty? && collection_ids.empty?)
          else
            (product_ids & in_cart).any? || (collection_ids & cart_collections).any?
          end
        end

        def in_range?(offer, merchandise_cents)
          config = hash(offer["config"])
          min = config["min_cart_cents"]
          max = config["max_cart_cents"]
          total = merchandise_cents.to_i
          return false if min.is_a?(Numeric) && min.positive? && total < min
          return false if max.is_a?(Numeric) && max.positive? && total > max

          true
        end

        # The products the popup offers: [{"product_id","title","image","variants" => [variant]}]
        #   variant = {"variant_id","title","image","unit_price_cents","offer_price_cents","compare_at_cents"}
        # Products already in the cart, and variants that cannot be sold, are left out.
        def products(offer:, catalog:, lines:)
          config = hash(offer["config"])
          catalog = hash(catalog)
          in_cart = product_lines(lines).map { |line| line["product_id"].to_s }
          limit = [[config["max_products"].to_i, 1].max, MAX_PRODUCTS].min

          Array(config["candidates"]).each_with_object([]) do |candidate, out|
            break out if out.length >= limit
            next unless candidate.is_a?(Hash)

            product_id = candidate["product_id"].to_s
            next if product_id.empty? || in_cart.include?(product_id)

            variants = strings(candidate["variant_ids"]).first(MAX_VARIANTS).filter_map do |variant_id|
              item = catalog[variant_id]
              next unless sellable?(item) && item["product_id"].to_s == product_id

              unit = item["unit_price_cents"].to_i
              price = offer_price(config, unit)
              compare = [item["compare_at_cents"].to_i, unit].max
              { "variant_id" => variant_id, "title" => item["variant_title"].to_s, "image" => item["image"],
                "unit_price_cents" => unit, "offer_price_cents" => price,
                "compare_at_cents" => compare > price ? compare : nil }
            end
            next if variants.empty?

            first = catalog[variants.first["variant_id"]]
            out << { "product_id" => product_id, "title" => first["title"].to_s,
                     "image" => first["image"] || variants.first["image"], "variants" => variants }
          end
        end

        # Price per unit after the rule's discount (never above the catalog price, never below 0).
        def offer_price(config, unit_price_cents)
          unit = [unit_price_cents.to_i, 0].max
          value = config["value"]
          price =
            case config["discount_type"].to_s
            when "percentage"
              percent = value.is_a?(Numeric) ? [[value, 0].max, 100].min : 0
              unit - Money.percent_of(unit, percent)
            when "fixed_amount"
              unit - (value.is_a?(Numeric) ? value.to_i : 0)
            when "fixed_price"
              value.is_a?(Numeric) ? value.to_i : unit
            else
              unit
            end
          [[price, 0].max, unit].min
        end

        # selected = [{"offer_id","variant_id","quantity"}] => extra line hashes (kind "pre_upsell").
        # Only the rule `match` picks counts; at most one line per product.
        def resolve(offer:, selected:, catalog:, lines:, locale: nil)
          return [] unless offer.is_a?(Hash)

          config = hash(offer["config"])
          offered = products(offer: offer, catalog: catalog, lines: lines)
          title = Offers.localized(config["title"], locale) || offer["name"].to_s
          max = config["quantity_picker"] == true ? [[config["max_quantity"].to_i, 1].max, MAX_QUANTITY].min : 1
          seen = {}

          Array(selected).filter_map do |choice|
            next unless choice.is_a?(Hash) && choice["offer_id"].to_s == offer["id"].to_s

            product = offered.find { |p| p["variants"].any? { |v| v["variant_id"] == choice["variant_id"].to_s } }
            next if product.nil? || seen[product["product_id"]]

            seen[product["product_id"]] = true
            variant = product["variants"].find { |v| v["variant_id"] == choice["variant_id"].to_s }
            item = hash(catalog)[variant["variant_id"]]
            quantity = [[choice["quantity"].to_i, 1].max, max].min
            limit = stock_limit(item)
            quantity = [quantity, limit].min if limit
            next if quantity < 1

            unit = variant["unit_price_cents"]
            price = variant["offer_price_cents"]
            { "key" => "pre_#{offer['id']}_#{variant['variant_id']}", "kind" => TYPE, "offer_id" => offer["id"],
              "offer_title" => title, "title" => product["title"], "variant_title" => variant["title"],
              "variant_id" => variant["variant_id"], "product_id" => product["product_id"],
              "collection_ids" => Array(item["collection_ids"]), "vendor" => item["vendor"],
              "image" => variant["image"] || product["image"], "quantity" => quantity,
              "original_unit_price_cents" => unit, "unit_discount_cents" => unit - price, "unit_price_cents" => price,
              "compare_at_cents" => variant["compare_at_cents"], "line_total_cents" => price * quantity,
              "grams" => item["grams"].to_i, "requires_shipping" => item["requires_shipping"] != false,
              "taxable" => item["taxable"] != false, "gift_card" => item["gift_card"] == true, "properties" => {} }
          end
        end

        # What the storefront needs to draw the popup of one rule.
        def public_offer(offer:, catalog:, lines:, locale: nil)
          config = hash(offer["config"])
          {
            "id" => offer["id"],
            "config" => config.slice("display", "position", "title", "body", "accept_label", "decline_label", "timer_seconds",
                                     "quantity_picker", "max_quantity", "discount_type", "value", "max_products",
                                     "min_cart_cents", "max_cart_cents"),
            "products" => products(offer: offer, catalog: catalog, lines: lines)
          }
        end

        # Variant ids whose prices the rules need (for CatalogService.variants).
        def variant_ids(offers)
          Array(offers).flat_map do |offer|
            Array(hash(hash(offer)["config"])["candidates"]).first(MAX_PRODUCTS * 2).flat_map do |candidate|
              candidate.is_a?(Hash) ? strings(candidate["variant_ids"]).first(MAX_VARIANTS) : []
            end
          end.uniq
        end

        private

        def sellable?(item)
          return false unless item.is_a?(Hash) && item["available"] != false && item["gift_card"] != true

          limit = stock_limit(item)
          limit.nil? || limit.positive?
        end

        # nil = no stock limit.
        def stock_limit(item)
          return nil unless item.is_a?(Hash)
          return nil unless item["inventory_policy"].to_s == "deny" && item["inventory_quantity"].is_a?(Integer)

          [item["inventory_quantity"], 0].max
        end

        def product_lines(lines)
          Array(lines).select do |line|
            line.is_a?(Hash) && (line["kind"].to_s.empty? || line["kind"].to_s == "product")
          end
        end

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def strings(value)
          Array(value).map { |item| item.to_s.strip }.reject(&:empty?)
        end
      end
    end
  end
end
