# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "money"
  require_relative "offers"
  require_relative "default_labels"
end

module CodForm
  module Engine
    # Bundles (offer_type "bundle"): two to six products sold together, with a discount on the
    # bundle. Shown on the product pages of its products and / or inside the form; however the
    # products got into the cart, the discount applies to every complete set in it.
    #
    #   config["product_ids"]   the bundle's products, in order
    #   config["candidates"]    [{"product_id","variant_ids"}] (CodForm::PreUpsellCatalog)
    #   config["discount_type"] none | percentage | fixed_amount (off one set) | fixed_price (of one set)
    #   config["show_on_product_page"], config["show_in_form"], config["position"]
    #
    # A set is one unit of every product of the bundle; the number of sets is the smallest
    # quantity among them. A set's discount is split across its products by their price, then
    # spread per unit over the lines (whole cents per unit, never more than configured).
    # One bundle per line: bundles are applied by priority.
    class Bundles
      TYPE = "bundle"
      MIN_PRODUCTS = 2
      MAX_PRODUCTS = 6
      MAX_VARIANTS = 10

      class << self
        # => copies of lines with the bundle discount on them ("bundle_offer_id", "bundle_title",
        #    "bundle_unit_discount_cents" added to "unit_discount_cents").
        def apply(lines:, offers:, locale: nil)
          list = Array(lines).map(&:dup)
          used = {}
          Offers.sorted(offers).each do |offer|
            next unless Offers.active?(offer) && offer["offer_type"].to_s == TYPE

            config = hash(offer["config"])
            product_ids = strings(config["product_ids"]).uniq.first(MAX_PRODUCTS)
            next if product_ids.length < MIN_PRODUCTS

            groups = product_ids.map do |pid|
              list.each_index.select { |i| !used[i] && eligible?(list[i]) && list[i]["product_id"].to_s == pid }
            end
            next if groups.any?(&:empty?)

            sets = groups.map { |indexes| indexes.sum { |i| list[i]["quantity"].to_i } }.min
            next unless sets.positive?

            # One set at the price of each product's first line.
            prices = groups.map { |indexes| unit_net(list[indexes.first]) }
            set_total = prices.sum
            discount = set_discount(config, set_total)
            next unless discount.positive?

            shares = Money.allocate(discount, prices)
            title = Offers.localized(config["title"], locale) || offer["name"].to_s
            title_local = Offers.explicit?(config["title"], locale)
            groups.each_with_index do |indexes, g|
              left = sets
              indexes.each do |i|
                line = list[i]
                used[i] = true
                break if left <= 0

                units = [line["quantity"].to_i, left].min
                left -= units
                per_unit = [(shares[g] * units) / line["quantity"].to_i, unit_net(line)].min
                next unless per_unit.positive?

                had = line["unit_discount_cents"].to_i.positive? && !line["discount_title"].to_s.empty?
                line["unit_discount_cents"] = line["unit_discount_cents"].to_i + per_unit
                line["bundle_unit_discount_cents"] = per_unit
                line["bundle_offer_id"] = offer["id"]
                line["bundle_title"] = title
                line["bundle_title_local"] = title_local
                line["discount_title"] = had ? "#{line['discount_title']} + #{title}" : title
                line["discount_value_type"] = "fixed"
                line["discount_percent"] = nil
              end
            end
          end
          list
        end

        # Discount on one set worth set_total cents.
        def set_discount(config, set_total)
          value = config["value"]
          amount =
            case config["discount_type"].to_s
            when "percentage" then Money.percent_of(set_total, value.is_a?(Numeric) ? [[value, 0].max, 100].min : 0)
            when "fixed_amount" then value.is_a?(Numeric) ? value.to_i : 0
            when "fixed_price" then value.is_a?(Numeric) ? set_total - value.to_i : 0
            else 0
            end
          [[amount, 0].max, set_total].min
        end

        # What the storefront needs to draw a bundle: its texts and its products with their
        # sellable variants (prices from the catalog, before the bundle discount).
        def public_bundle(offer:, catalog:, locale: nil)
          config = hash(offer["config"])
          catalog = hash(catalog)
          by_product = Array(config["candidates"]).select { |c| c.is_a?(Hash) }.to_h { |c| [c["product_id"].to_s, c] }
          products = strings(config["product_ids"]).uniq.first(MAX_PRODUCTS).filter_map do |pid|
            variants = strings(hash(by_product[pid])["variant_ids"]).first(MAX_VARIANTS).filter_map do |vid|
              item = catalog[vid]
              next unless item.is_a?(Hash) && item["available"] != false && item["product_id"].to_s == pid

              { "variant_id" => vid, "title" => item["variant_title"].to_s, "image" => item["image"],
                "price_cents" => item["unit_price_cents"].to_i, "compare_at_cents" => item["compare_at_cents"] }
            end
            next if variants.empty?

            first = catalog[variants.first["variant_id"]]
            { "product_id" => pid, "title" => first["title"].to_s, "image" => first["image"] || variants.first["image"],
              "variants" => variants }
          end
          return nil if products.length < MIN_PRODUCTS || products.length < strings(config["product_ids"]).uniq.first(MAX_PRODUCTS).length

          {
            "id" => offer["id"],
            "config" => config.slice("title", "body", "button_label", "discount_type", "value", "position", "page_position", "page_selector",
                                     "show_in_form", "show_on_product_page").tap do |out|
                          # English default texts carry their translations (the product-page widget picks one).
                          %w[title body button_label].each { |key| out[key] = DefaultLabels.localize(out[key]) if out.key?(key) }
                        end,
            "products" => products
          }
        end

        # Bundles with at least one product in the cart (the form shows them).
        def for_cart(offers:, lines:)
          in_cart = Array(lines).select { |line| line.is_a?(Hash) }.map { |line| line["product_id"].to_s }
          Offers.sorted(offers).select do |offer|
            Offers.active?(offer) && offer["offer_type"].to_s == TYPE &&
              (strings(hash(offer["config"])["product_ids"]) & in_cart).any?
          end
        end

        def for_product(offers:, product_id:)
          Offers.sorted(offers).select do |offer|
            Offers.active?(offer) && offer["offer_type"].to_s == TYPE &&
              strings(hash(offer["config"])["product_ids"]).include?(product_id.to_s)
          end
        end

        def variant_ids(offers)
          Array(offers).flat_map do |offer|
            Array(hash(hash(offer)["config"])["candidates"]).first(MAX_PRODUCTS).flat_map do |candidate|
              candidate.is_a?(Hash) ? strings(candidate["variant_ids"]).first(MAX_VARIANTS) : []
            end
          end.uniq
        end

        private

        def eligible?(line)
          kind = line["kind"].to_s
          (kind.empty? || kind == "product") && line["quantity"].to_i.positive? && !Offers.bundle_line?(line)
        end

        def unit_net(line)
          [line["unit_price_cents"].to_i - line["unit_discount_cents"].to_i, 0].max
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
