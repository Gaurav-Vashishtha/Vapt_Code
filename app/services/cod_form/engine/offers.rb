# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "money"
end

module CodForm
  module Engine
    # Offer pricing (ARCHITECTURE E.6 / C.4, OFF-1..11).
    #
    # Stacking order (OFF-8): quantity offer -> downsell -> discount code.
    # Quantity offer and downsell are per-unit line discounts (integer cents per unit, so
    # line discount == unit discount x quantity exactly); the discount code is the single
    # order-level discount.
    class Offers
      MAX_BUMPS_SHOWN = 3

      class << self
        # First active quantity offer (by priority, then id) that targets the line.
        def match_quantity_offer(offers:, line:)
          sorted(offers).find do |offer|
            active?(offer) && quantity_type?(offer) && targets_line?(offer, line)
          end
        end

        # => copies of lines with "unit_discount_cents", "discount_title", "offer_id", "tier_index"
        #    (+ "discount_value_type" / "discount_percent" used by DraftOrderBuilder).
        def apply_quantity_tiers(lines:, offers:, locale: nil)
          Array(lines).map do |raw|
            line = raw.dup
            line["unit_discount_cents"] = line["unit_discount_cents"].to_i
            line["discount_title"] ||= nil
            line["offer_id"] ||= nil
            line["tier_index"] ||= nil
            next line unless tier_eligible?(line)

            offer = match_quantity_offer(offers: offers, line: line)
            next line unless offer

            config = hash(offer["config"])
            tiers = sorted_tiers(config)
            index = tier_index_for(tiers, line["quantity"].to_i, config["apply_to_higher_quantities"] != false)
            next line unless index

            tier = tiers[index]
            price = line["unit_price_cents"].to_i
            quantity = line["quantity"].to_i
            discount = [[tier_unit_discount(tier, price, quantity), 0].max, price].min
            line["offer_id"] = offer["id"]
            line["tier_index"] = index
            line["unit_discount_cents"] = discount
            if discount.positive?
              line["discount_title"] = localized(tier["label"], locale) || localized(config["title"], locale) || offer["name"].to_s
              # Written by the merchant in the buyer's language (not the default text / offer name)?
              line["discount_title_local"] = explicit?(tier["label"], locale) ||
                                             (localized(tier["label"], locale).nil? && explicit?(config["title"], locale))
              percentage = tier["discount_type"].to_s == "percentage"
              line["discount_value_type"] = percentage ? "percentage" : "fixed"
              line["discount_percent"] = percentage ? tier["value"] : nil
            end
            line
          end
        end

        # selected = [{"offer_id","quantity"}] => extra line hashes (kind "bump").
        # Only the first three matching bumps (by priority) can be selected.
        def resolve_bumps(offers:, selected:, cart:, catalog:, locale: nil)
          cart_lines = Array(hash(cart)["lines"])
          catalog = hash(catalog)
          eligible = sorted(offers).select do |offer|
            active?(offer) && offer_type(offer, "bump") == "bump" && targets_cart?(offer, cart_lines)
          end.first(MAX_BUMPS_SHOWN)

          seen = {}
          Array(selected).filter_map do |choice|
            next unless choice.is_a?(Hash)

            offer = eligible.find { |candidate| candidate["id"].to_s == choice["offer_id"].to_s }
            next if offer.nil? || seen[offer["id"].to_s]

            seen[offer["id"].to_s] = true
            build_bump_line(offer, choice, catalog, locale)
          end
        end

        # Adds a per-unit discount on product lines, on top of the quantity-offer discount.
        # offer = downsell offer wrapper ({"id","config"=>{"discount_type","value",...}}) or the bare config.
        def apply_downsell(lines:, offer:, locale: nil)
          list = Array(lines).map(&:dup)
          return list unless offer.is_a?(Hash)

          config = offer["config"].is_a?(Hash) ? offer["config"] : offer
          value = config["value"]
          return list unless value.is_a?(Numeric) && value.positive?

          targets = list.select { |line| product_line?(line) && line["quantity"].to_i.positive? }
          return list if targets.empty?

          title = localized(config["title"], locale) || offer["name"].to_s
          title_local = explicit?(config["title"], locale)
          extras =
            case config["discount_type"].to_s
            when "percentage"
              targets.map { |line| Money.percent_of(unit_net(line), [value, 100].min) }
            when "fixed_amount"
              downsell_fixed(targets, value.to_i)
            else
              return list
            end

          targets.each_with_index do |line, index|
            extra = [extras[index], unit_net(line)].min
            next unless extra.positive?

            had_tier = line["unit_discount_cents"].to_i.positive?
            line["unit_discount_cents"] = line["unit_discount_cents"].to_i + extra
            line["downsell_unit_discount_cents"] = extra
            line["downsell_offer_id"] = offer["id"]
            line["downsell_title"] = title
            line["downsell_title_local"] = title_local
            line["discount_title"] = had_tier && !line["discount_title"].to_s.empty? ? "#{line['discount_title']} + #{title}" : title
            line["discount_value_type"] = "fixed"
            line["discount_percent"] = nil
          end
          list
        end

        # code = normalised hash from CodForm::DiscountCodeService ("value" of a fixed_amount code is in cents).
        # lines carry "unit_price_cents", "unit_discount_cents", "quantity" (already discounted by offers).
        # => {"status"=>"applied"|"not_applicable"|"not_combinable"|"minimum_not_met", "amount_cents"=>Integer, "free_shipping"=>bool}
        def apply_discount_code(lines:, code:, subtotal_cents:, quantity:, stacking:)
          none = { "status" => "not_applicable", "amount_cents" => 0, "free_shipping" => false }
          return none unless code.is_a?(Hash) && code["error"].nil? && !code["kind"].to_s.empty?

          list = Array(lines).select { |line| line.is_a?(Hash) }
          combine = hash(stacking)["codes_combine_with_offers"] == true
          offers_applied = list.any? { |line| line["unit_discount_cents"].to_i.positive? && line["kind"].to_s != "bump" }
          return none.merge("status" => "not_combinable") if !combine && offers_applied

          min_subtotal = code["min_subtotal_cents"]
          min_quantity = code["min_quantity"]
          if (min_subtotal.is_a?(Numeric) && subtotal_cents.to_i < min_subtotal) ||
             (min_quantity.is_a?(Numeric) && quantity.to_i < min_quantity)
            return none.merge("status" => "minimum_not_met")
          end

          kind = code["kind"].to_s
          return { "status" => "applied", "amount_cents" => 0, "free_shipping" => true } if kind == "free_shipping"

          eligible = list.select { |line| code_applies?(code["applies_to"], line) }
          eligible_total = eligible.sum { |line| line_net(line) }
          return none unless eligible_total.positive?

          value = code["value"]
          return none unless value.is_a?(Numeric) && value.positive?

          amount =
            case kind
            when "percentage" then Money.percent_of(eligible_total, [value, 100].min)
            when "fixed_amount" then value.round
            else return none
            end
          amount = [amount, eligible_total].min
          return none unless amount.positive?

          { "status" => "applied", "amount_cents" => amount, "free_shipping" => false }
        end

        # => [{"offer_id","kind","threshold_cents","remaining_cents","reached"}]
        def evaluate_thresholds(offers:, merchandise_total_cents:)
          total = merchandise_total_cents.to_i
          sorted(offers).filter_map do |offer|
            next unless active?(offer) && offer_type(offer, "threshold") == "threshold"

            config = hash(offer["config"])
            threshold = config["threshold_cents"].to_i
            remaining = [threshold - total, 0].max
            { "offer_id" => offer["id"], "kind" => config["kind"].to_s, "threshold_cents" => threshold,
              "remaining_cents" => remaining, "reached" => remaining.zero? }
          end
        end

        # Per-unit discount of a tier for unit price p and quantity n (E.6).
        def tier_unit_discount(tier, unit_price_cents, quantity)
          value = tier["value"]
          return 0 unless value.is_a?(Numeric) && quantity.positive?

          case tier["discount_type"].to_s
          when "percentage" then Money.percent_of(unit_price_cents, [[value, 0].max, 100].min)
          when "unit_price" then [unit_price_cents - value.round, 0].max
          when "fixed_amount" then value.to_i / quantity
          else 0
          end
        end

        # Lines carrying bundle-app properties (key starting with "_") never get a tier (OFF-9).
        def bundle_line?(line)
          properties = line["properties"]
          properties.is_a?(Hash) && properties.keys.any? { |key| key.to_s.start_with?("_") }
        end

        def localized(map, locale = nil)
          return (map.to_s.strip.empty? ? nil : map.to_s) unless map.is_a?(Hash)

          keys = [locale.to_s, locale.to_s.split(/[-_]/).first.to_s, "default", "en"].reject(&:empty?)
          keys.each do |key|
            text = map[key].to_s.strip
            return text unless text.empty?
          end
          map.values.map { |value| value.to_s.strip }.find { |text| !text.empty? }
        end

        # True when the map has its own text for the locale (or its language part), as opposed to a
        # text that falls back to "default" / "en". The storefront translates the fallbacks itself.
        def explicit?(map, locale = nil)
          return false unless map.is_a?(Hash)

          [locale.to_s, locale.to_s.split(/[-_]/).first.to_s].reject(&:empty?).uniq.any? { |key| !map[key].to_s.strip.empty? }
        end

        def targets_line?(offer, line)
          targeting = hash(offer["targeting"])
          return true if targeting["scope"].to_s != "selected"

          strings(targeting["product_ids"]).include?(line["product_id"].to_s) ||
            (strings(targeting["collection_ids"]) & strings(line["collection_ids"])).any?
        end

        def targets_cart?(offer, lines)
          return true if hash(offer["targeting"])["scope"].to_s != "selected"

          Array(lines).any? { |line| line.is_a?(Hash) && targets_line?(offer, line) }
        end

        def sorted(offers)
          Array(offers).select { |offer| offer.is_a?(Hash) }.each_with_index.sort_by do |offer, index|
            [offer["priority"].to_i, offer["id"].is_a?(Integer) ? offer["id"] : 0, index]
          end.map(&:first)
        end

        def active?(offer)
          status = offer["status"].to_s
          status.empty? || status == "active"
        end

        private

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def strings(value)
          Array(value).map { |item| item.to_s.strip }.reject(&:empty?)
        end

        def offer_type(offer, default)
          type = offer["offer_type"].to_s
          type.empty? ? default : type
        end

        def quantity_type?(offer)
          offer_type(offer, "quantity") == "quantity"
        end

        def product_line?(line)
          kind = line["kind"].to_s
          kind.empty? || kind == "product"
        end

        def tier_eligible?(line)
          product_line?(line) && !bundle_line?(line) && line["quantity"].to_i.positive?
        end

        def sorted_tiers(config)
          Array(config["tiers"]).select { |tier| tier.is_a?(Hash) && tier["quantity"].to_i.positive? }
                                .each_with_index.sort_by { |tier, index| [tier["quantity"].to_i, index] }.map(&:first)
        end

        def tier_index_for(tiers, quantity, higher)
          if higher
            index = nil
            tiers.each_with_index { |tier, i| index = i if tier["quantity"].to_i <= quantity }
            index
          else
            tiers.index { |tier| tier["quantity"].to_i == quantity }
          end
        end

        def unit_net(line)
          [line["unit_price_cents"].to_i - line["unit_discount_cents"].to_i, 0].max
        end

        def line_net(line)
          unit_net(line) * line["quantity"].to_i
        end

        # Fixed downsell: split across lines by line total, then per unit (floor). Left-over cents are
        # handed to lines whose quantity still fits, so charged == displayed and never exceeds the value.
        def downsell_fixed(targets, value)
          totals = targets.map { |line| line_net(line) }
          amount = [[value, 0].max, totals.sum].min
          shares = Money.allocate(amount, totals)
          units = targets.each_with_index.map { |line, index| shares[index] / line["quantity"].to_i }
          left = amount - targets.each_with_index.sum { |line, index| units[index] * line["quantity"].to_i }
          order = targets.each_index.sort_by { |index| [targets[index]["quantity"].to_i, index] }
          progress = true
          while left.positive? && progress
            progress = false
            order.each do |index|
              quantity = targets[index]["quantity"].to_i
              next if quantity > left || units[index] >= unit_net(targets[index])

              units[index] += 1
              left -= quantity
              progress = true
            end
          end
          units
        end

        def code_applies?(applies_to, line)
          return true unless applies_to.is_a?(Hash)
          return true if applies_to["all"] == true

          product_ids = strings(applies_to["product_ids"])
          collection_ids = strings(applies_to["collection_ids"])
          return true if product_ids.empty? && collection_ids.empty?

          product_id = line["product_id"].to_s
          return false if product_id.empty?

          product_ids.include?(product_id) || (strings(line["collection_ids"]) & collection_ids).any?
        end

        def build_bump_line(offer, choice, catalog, locale)
          config = hash(offer["config"])
          max = [config["max_quantity"].to_i, 1].max
          quantity = config["quantity_picker"] == true ? [[choice["quantity"].to_i, 1].max, max].min : 1
          title = localized(config["title"], locale) || offer["name"].to_s
          base = { "key" => "bump_#{offer['id']}", "kind" => "bump", "offer_id" => offer["id"],
                   "title" => title, "quantity" => quantity, "properties" => {} }

          if config["kind"].to_s == "variant"
            variant_id = config["variant_id"].to_s
            item = catalog[variant_id]
            return nil unless item.is_a?(Hash) && item["available"] != false

            original = item["unit_price_cents"].to_i
            configured = config["price_cents"]
            price = configured.is_a?(Numeric) ? [[configured.to_i, 0].max, original].min : original
            base.merge(
              "bump_kind" => "variant", "variant_id" => variant_id, "product_id" => item["product_id"].to_s,
              "collection_ids" => Array(item["collection_ids"]), "vendor" => item["vendor"],
              "image" => item["image"] || config["image_url"],
              "original_unit_price_cents" => original, "unit_discount_cents" => original - price,
              "unit_price_cents" => price,
              "compare_at_cents" => config["compare_at_cents"] || (original > price ? original : item["compare_at_cents"]),
              "line_total_cents" => price * quantity,
              "grams" => item["grams"].to_i, "requires_shipping" => item["requires_shipping"] != false,
              "taxable" => item["taxable"] != false, "gift_card" => item["gift_card"] == true
            )
          else
            price = [config["price_cents"].to_i, 0].max
            base.merge(
              "bump_kind" => "custom", "variant_id" => nil, "product_id" => nil, "collection_ids" => [],
              "image" => config["image_url"],
              "original_unit_price_cents" => price, "unit_discount_cents" => 0, "unit_price_cents" => price,
              "compare_at_cents" => config["compare_at_cents"], "line_total_cents" => price * quantity,
              "grams" => 0, "requires_shipping" => config["requires_shipping"] == true,
              "taxable" => config["taxable"] != false, "gift_card" => false
            )
          end
        end
      end
    end
  end
end
