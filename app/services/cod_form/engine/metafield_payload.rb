# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "defaults"
  require_relative "default_labels"
  require_relative "form_config"
end

module CodForm
  module Engine
    # Builds the codk.cod_form shop metafield (ARCHITECTURE C.1).
    class MetafieldPayload
      MAX_IDS = 250
      TIER_TYPES = %w[none percentage fixed_amount unit_price].freeze

      class << self
        # input = {"enabled","api","shop","version","general","button"=>{"preset","config"},"rules","quantity_offers",
        #          "features","cap_fallback","test_only"} (+ optional "prepaid_label", "preview")
        def build(input)
          input = hash(input)
          general = hash(input["general"])
          defaults = Defaults.general
          button = hash(input["button"])
          config = hash(button["config"])
          default_button = Defaults.button_config
          products = hash(general["products"])
          order_total = hash(general["order_total"])
          pages = defaults["pages"].merge(hash(general["pages"]).select { |key, _| defaults["pages"].key?(key) })
          embedded = hash(general["embedded"])

          vis_overflow = false
          vis = { "scope" => products["scope"].to_s == "selected" ? "selected" : "all" }
          { "inc_p" => "include_product_ids", "inc_c" => "include_collection_ids",
            "exc_p" => "exclude_product_ids", "exc_c" => "exclude_collection_ids" }.each do |short, long|
            vis[short], over = cap(products[long])
            vis_overflow ||= over
          end
          vis["min_cents"] = cents(order_total["min_cents"])
          vis["max_cents"] = cents(order_total["max_cents"])
          vis["hide_oos"] = general.key?("hide_out_of_stock") ? general["hide_out_of_stock"] == true : true
          vis["overflow"] = vis_overflow

          {
            "v" => input["version"].to_i,
            "enabled" => input["enabled"] == true,
            "api" => input["api"].to_s.sub(%r{/+\z}, ""),
            "shop" => input["shop"].to_s,
            "cap_fallback" => input["cap_fallback"] == true,
            "test_only" => input["test_only"] == true,
            "countries" => Array(general["countries"]).map { |c| c.to_s.upcase }.reject(&:empty?).uniq,
            "pages" => pages.transform_values { |value| value == true },
            "vis" => vis,
            "rules" => rules(hash(input["rules"])),
            "button" => localized_button({ "preset" => %w[A B C].include?(button["preset"].to_s) ? button["preset"].to_s : Defaults.button_preset }
                        .merge(default_button["button"].merge(hash(config["button"])))),
            "theme" => default_button["theme"].merge(hash(config["theme"])),
            "features" => Array(input["features"]).map(&:to_s).uniq,
            "qo" => Array(input["quantity_offers"]).filter_map { |offer| quantity_offer(offer) },
            "embedded" => { "enabled" => embedded["enabled"] == true, "selector" => embedded["selector"].to_s,
                            "position" => %w[before after].include?(embedded["position"].to_s) ? embedded["position"].to_s : "after" },
            "prepaid_label" => input["prepaid_label"].is_a?(Hash) ? input["prepaid_label"] : { "default" => "" },
            "rtl_locales" => Defaults::RTL_LOCALES.dup,
            # Setup → Form language: the embed shows the button, widgets and form in it ("" = storefront language).
            "lang" => FormConfig.language(general["language"]),
            "preview" => input["preview"] == true
          }.tap do |out|
            # Bundles shown on product pages: the embed loads the bundle widget on these products.
            list = Array(input["bundles"]).filter_map { |offer| bundle(offer) }
            out["bundles"] = list if list.any?
          end
        end

        private

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        # => [list capped at 250, overflowed?]
        def cap(value)
          list = (value.is_a?(Array) ? value : value.to_s.split(",")).map { |item| item.to_s.strip }.reject(&:empty?).uniq
          [list.first(MAX_IDS), list.length > MAX_IDS]
        end

        def cents(value)
          value.is_a?(Numeric) && value.positive? ? value.round : nil
        end

        # E.3 rules hash -> page-load rules mirrored to the storefront (VIS-6)
        def rules(source)
          overflow = false
          out = {}
          { "hide_p" => "deny_product_ids", "show_p" => "allow_product_ids", "hide_v" => "deny_variant_ids",
            "hide_c" => "deny_collection_ids", "show_c" => "allow_collection_ids",
            "hide_vendors" => "deny_vendors", "show_vendors" => "allow_vendors" }.each do |short, long|
            list, over = cap(source[long])
            list = list.map(&:downcase) if short.end_with?("vendors")
            out[short] = list
            overflow ||= over
          end
          out["min_cents"] = cents(source["min_total_cents"])
          out["max_cents"] = cents(source["max_total_cents"])
          out["overflow"] = overflow
          out
        end

        # Offer wrapper (C.4 quantity) -> compact "qo" entry; only offers shown on the product page.
        def quantity_offer(offer)
          return nil unless offer.is_a?(Hash)

          config = hash(offer["config"])
          return nil if config["show_widget_on_product_page"] == false

          targeting = hash(offer["targeting"])
          all = targeting["scope"].to_s != "selected"
          products, = cap(targeting["product_ids"])
          collections, = cap(targeting["collection_ids"])
          tiers = Array(config["tiers"]).select { |tier| tier.is_a?(Hash) }.sort_by { |tier| tier["quantity"].to_i }.first(5).map do |tier|
            type = tier["discount_type"].to_s
            { "q" => tier["quantity"].to_i, "type" => TIER_TYPES.include?(type) ? type : "none",
              "value" => tier["value"].is_a?(Numeric) ? tier["value"] : 0,
              "label" => DefaultLabels.localize(label(tier["label"])), "badge" => DefaultLabels.localize(label(tier["badge"])),
              "image" => tier["image_url"].to_s, "pre" => tier["preselected"] == true }
          end
          return nil if tiers.empty?

          { "id" => offer["id"], "p" => all ? [] : products, "c" => all ? [] : collections, "all" => all,
            "layout" => %w[cards list compact].include?(config["layout"].to_s) ? config["layout"].to_s : "cards",
            "title" => DefaultLabels.localize(label(config["title"])), "tiers" => tiers }
        end

        def bundle(offer)
          return nil unless offer.is_a?(Hash)

          config = hash(offer["config"])
          return nil if config["show_on_product_page"] == false

          products, = cap(config["product_ids"])
          products.length >= 2 ? { "id" => offer["id"], "p" => products } : nil
        end

        # Button, sticky, cart and drawer labels: COD King's English defaults get their translations.
        def localized_button(button)
          out = button.merge("labels" => DefaultLabels.localize(button["labels"]))
          %w[sticky cart drawer].each do |key|
            part = hash(out[key])
            out[key] = part.merge("labels" => DefaultLabels.localize(part["labels"])) if part.key?("labels")
          end
          out
        end

        def label(value)
          value.is_a?(Hash) ? value : { "default" => value.to_s }
        end
      end
    end
  end
end
