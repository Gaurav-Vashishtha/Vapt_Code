# frozen_string_literal: true

require "json"
require "digest"

unless defined?(::Rails)
  %w[money postal_matcher cod_rules visibility shipping_rates offers pre_upsells bundles cod_fee partial_rules otp_policy].each do |name|
    require_relative name
  end
end

module CodForm
  module Engine
    # The quote orchestrator used by session, quote and submit (ARCHITECTURE E.7 / D.2).
    #
    # Totals (integer cents, exact by construction):
    #   subtotal_cents           = sum(product line unit price x quantity)
    #   discount_total_cents     = sum(per-unit line discount x quantity) + discount code amount
    #   merchandise_total_cents  = subtotal - discount_total + bump lines (gift lines are 0)
    #   total_cents              = merchandise_total + shipping + COD fee (+ tax when calculated and not included)
    # DraftOrderBuilder sends exactly these numbers, so the order total equals the quote total.
    class Quote
      BAND_RANK = { "low" => 0, "medium" => 1, "high" => 2 }.freeze
      BLOCK_MESSAGE_KEYS = {
        "phone_limit" => "error_limit_reached", "email_limit" => "error_limit_reached",
        "ip_limit" => "error_limit_reached", "max_quantity" => "error_max_quantity"
      }.freeze
      CODE_MESSAGE_KEYS = {
        "not_combinable" => "error_discount_not_combinable", "minimum_not_met" => "error_discount_minimum"
      }.freeze

      class << self
        def build(input)
          input = hash(input)
          currency = input["currency"].to_s
          stage = %w[page quote submit].include?(input["stage"].to_s) ? input["stage"].to_s : "quote"
          locale = input["locale"]
          general = hash(input["general"])
          fraud = hash(input["fraud"])
          address = hash(input["address"])
          contact = hash(input["contact"])
          offers = hash(input["offers"])
          warnings = []

          # (1) availability and max_quantity per line
          lines = Array(input["lines"]).select { |line| line.is_a?(Hash) }.each_with_index.map do |raw, index|
            line = raw.dup
            line["key"] = "l#{index}" if line["key"].to_s.empty?
            line["kind"] = "product"
            line["quantity"] = [line["quantity"].to_i, 1].max
            line["unit_price_cents"] = [line["unit_price_cents"].to_i, 0].max
            line["available"] = line["available"] != false
            line["max_quantity"] = max_quantity(line, fraud)
            line["properties"] = hash(line["properties"])
            line
          end
          if lines.any? { |line| !line["available"] || (line["max_quantity"] && line["quantity"] > line["max_quantity"]) }
            warnings << "out_of_stock"
          end

          # (2) quantity offers, (3) downsell
          lines = Offers.apply_quantity_tiers(lines: lines, offers: Array(offers["quantity"]), locale: locale)
          downsell = accepted_downsell(input, offers)
          lines = Offers.apply_downsell(lines: lines, offer: downsell, locale: locale) if downsell
          # (3a) bundles: a discount on every complete set of a bundle's products in the cart
          lines = Bundles.apply(lines: lines, offers: Array(offers["bundles"]), locale: locale)

          # (3b) the store's own automatic discounts (Buy X get Y, automatic % off ...). Shopify
          # worked them out for this cart (CodForm::AutomaticDiscountService); here they are amounts
          # per line plus an order-level rest, and the draft order carries them as explicit discounts.
          auto_input = hash(input["automatic_discount"])
          auto_by_line = hash(auto_input["lines"])
          auto_title = auto_input["title"].to_s
          lines.each do |line|
            line["line_subtotal_cents"] = line["unit_price_cents"] * line["quantity"]
            line["discount_cents"] = line["unit_discount_cents"].to_i * line["quantity"]
            own_total = line["line_subtotal_cents"] - line["discount_cents"]
            line["auto_cents"] = [[auto_by_line[line["key"]].to_i, 0].max, own_total].min
            line["auto_title"] = auto_title
            line["line_total_cents"] = own_total - line["auto_cents"]
          end
          auto_lines = lines.sum { |line| line["auto_cents"] }

          # (4) bumps
          bumps = Offers.resolve_bumps(offers: Array(offers["bumps"]), selected: Array(input["selected_bumps"]),
                                       cart: { "lines" => lines }, catalog: hash(input["bump_catalog"]), locale: locale)
          warnings << "bump_unavailable" if bumps.length < Array(input["selected_bumps"]).map { |b| b.is_a?(Hash) ? b["offer_id"].to_s : nil }.compact.uniq.length

          subtotal = lines.sum { |line| line["line_subtotal_cents"] }
          line_discount = lines.sum { |line| line["discount_cents"] }

          # (4b) pre-purchase upsell: the one rule shown for this cart (its cart value range is on
          # the products after their offers), and the items the buyer added from its popup
          pre_offer = PreUpsells.match(offers: Array(offers["pre_upsells"]), lines: lines,
                                       merchandise_cents: subtotal - line_discount - auto_lines, catalog: hash(input["bump_catalog"]))
          selected_pre = Array(input["selected_pre_upsells"]).select { |choice| choice.is_a?(Hash) }
          pre_lines = PreUpsells.resolve(offer: pre_offer, selected: selected_pre, catalog: hash(input["bump_catalog"]),
                                         lines: lines, locale: locale)
          warnings << "pre_upsell_unavailable" if pre_lines.length < selected_pre.length
          bumps += pre_lines

          bumps_total = bumps.sum { |line| line["line_total_cents"] }
          before_code = subtotal - line_discount - auto_lines + bumps_total
          total_quantity = lines.sum { |line| line["quantity"] }

          # (5) discount code
          code_input = input["discount_code"]
          code_result = nil
          code_output = nil
          if code_input.is_a?(Hash) && !code_input["code"].to_s.empty?
            if code_input["error"]
              code_output = { "code" => code_input["code"].to_s, "status" => "invalid", "message_key" => "error_discount_invalid",
                              "error" => code_input["error"].to_s }
            else
              code_lines = lines + bumps.map { |bump| bump.merge("unit_discount_cents" => 0) }
              code_result = Offers.apply_discount_code(lines: code_lines, code: code_input, subtotal_cents: before_code,
                                                       quantity: total_quantity, stacking: hash(general["discounts"]))
              status = code_result["status"]
              code_output = { "code" => code_input["code"].to_s, "status" => status,
                              "message_key" => status == "applied" ? nil : (CODE_MESSAGE_KEYS[status] || "error_discount_invalid") }
            end
          end
          code_applied = !code_result.nil? && code_result["status"] == "applied"
          code_amount = code_applied ? code_result["amount_cents"] : 0

          # (5b) what Shopify gave that is not on a product line (order-level automatic discounts,
          # discounts on bump / gift lines)
          known_keys = lines.map { |line| line["key"] }
          auto_rest = auto_input["order_cents"].to_i + auto_by_line.sum { |key, cents| known_keys.include?(key) ? 0 : cents.to_i }
          auto_order = [[auto_rest, 0].max, before_code - code_amount].min
          auto_amount = auto_lines + auto_order
          merchandise = before_code - code_amount - auto_order

          # (6) thresholds (+ free gift lines, priced 0)
          thresholds = Offers.evaluate_thresholds(offers: Array(offers["thresholds"]), merchandise_total_cents: merchandise)
          gifts = gift_lines(thresholds, Array(offers["thresholds"]), hash(input["bump_catalog"]), warnings)
          thresholds = with_gift_preview(thresholds, Array(offers["thresholds"]), hash(input["bump_catalog"]))
          extra = bumps + gifts
          free_shipping = (code_applied && code_result["free_shipping"] == true) ||
                          thresholds.any? { |t| t["kind"] == "free_shipping" && t["reached"] }

          # (7) eligibility
          rule_cart = { "lines" => lines, "total_cents" => merchandise, "total_quantity" => total_quantity }
          eligibility = eligibility(input, general, fraud, rule_cart, address, contact, stage)

          # (8) shipping
          shipping_lines = lines + extra
          selection = ShippingRates.select(
            rates: Array(input["shipping_rates"]), cart: { "lines" => shipping_lines }, address: address,
            subtotal_cents: merchandise, currency: currency, selected_id: input["selected_shipping_rate_id"],
            free_shipping: free_shipping
          )
          shipping_cents = selection["price_cents"]
          shipping = selection.merge(
            "hide_selector" => selection["rates"].length == 1 && input["hide_shipping_selector_when_single"] != false,
            "message" => nil,
            "message_key" => if !selection["none_available"] then nil
                             elsif selection["pending_address"] then "shipping_enter_address"
                             else "error_no_shipping"
                             end
          )

          # (9) COD fee on merchandise after discounts + shipping
          fee = CodFee.compute(config: hash(input["cod_fee"]), base_cents: merchandise + shipping_cents, currency: currency)

          # (10) tax
          tax = tax(hash(input["tax"]))
          tax_added = tax["status"] == "calculated" && tax["required"] ? tax["amount_cents"] : 0

          # (11) totals
          discount_total = line_discount + code_amount + auto_amount
          total = merchandise + shipping_cents + fee["amount_cents"] + tax_added
          savings = discount_total + lines.sum do |line|
            compare = line["compare_at_cents"].to_i
            compare > line["unit_price_cents"] ? (compare - line["unit_price_cents"]) * line["quantity"] : 0
          end

          # (12) payment options
          totals = { "subtotal_cents" => subtotal, "line_discount_cents" => line_discount + auto_lines, "order_discount_cents" => code_amount + auto_order,
                     "merchandise_total_cents" => merchandise, "shipping_cents" => shipping_cents,
                     "cod_fee_cents" => fee["amount_cents"], "tax_cents" => tax_added, "total_cents" => total }
          matched = PartialRules.match(rules: Array(input["partial_rules"]), cart: rule_cart, address: address,
                                       contact: contact, risk: input["risk"])
          payment_options = PartialRules.options(rules: matched, totals: totals, cod_allowed: eligibility["cod_allowed"],
                                                 money_format: input["money_format"])
          prepaid_offer = prepaid_offer(input, rule_cart, address, contact, totals, eligibility, fee)

          # (13) OTP
          otp = hash(input["otp"])
          otp_required = OtpPolicy.required?(
            shop_enabled: otp["shop_enabled"] == true, mode: otp["mode"],
            risk_band: hash(input["risk"])["band"], target_band: otp["risk_band"], verified: otp["verified"] == true
          )

          draft = draft(currency, lines, extra, code_input, code_amount, selection, shipping_lines, fee, auto_order, auto_title)
          quote = {
            "currency" => currency,
            "lines" => lines.map { |line| public_line(line) },
            "extra_lines" => extra.map { |line| public_extra(line) },
            "quantity_offer" => quantity_offer(lines),
            "discounts" => discounts(lines, code_input, code_amount) +
                           (auto_amount.positive? ? [{ "kind" => "automatic", "title" => auto_title, "amount_cents" => auto_amount }] : []),
            "discount_code" => code_output,
            "shipping" => shipping,
            "cod_fee" => fee,
            "tax" => tax,
            "subtotal_cents" => subtotal,
            "discount_total_cents" => discount_total,
            "merchandise_total_cents" => merchandise,
            "shipping_cents" => shipping_cents,
            "total_cents" => total,
            "savings_cents" => savings,
            "eligibility" => eligibility,
            "payment_options" => payment_options,
            "prepaid_offer" => prepaid_offer,
            "otp_required" => otp_required,
            "thresholds" => thresholds,
            "warnings" => warnings.uniq,
            "pre_upsell" => pre_offer ? { "offer_id" => pre_offer["id"] } : nil,
            # What the browser needs to show a new total at once when only the address or the
            # chosen shipping rate changes; the next server quote always replaces it.
            "local" => local_pricing(input, shipping_lines, merchandise, currency, free_shipping, fee, tax_added),
            "_draft" => draft
          }
          quote["_fingerprint"] = fingerprint(draft, total)
          quote
        end

        # SHA-256 of the canonical JSON of lines, discounts, shipping, fee and total.
        def fingerprint(draft, total_cents)
          Digest::SHA256.hexdigest(JSON.generate(canonical("draft" => draft, "total_cents" => total_cents)))
        end

        private

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def canonical(value)
          case value
          when Hash then value.keys.map(&:to_s).sort.each_with_object({}) { |key, out| out[key] = canonical(value[key]) }
          when Array then value.map { |item| canonical(item) }
          else value
          end
        end

        # nil = no limit known.
        def max_quantity(line, fraud)
          limits = []
          if line["inventory_policy"].to_s == "deny" && line["inventory_quantity"].is_a?(Integer)
            limits << [line["inventory_quantity"], 0].max
          end
          cap = fraud["max_quantity_per_order"]
          limits << cap.to_i if cap.is_a?(Numeric) && cap.positive?
          limits.min
        end

        # The downsell applies only once the buyer accepted it: input["downsell_offer_id"] == offer id.
        def accepted_downsell(input, offers)
          offer = offers["downsell"]
          accepted = input["downsell_offer_id"]
          return nil unless offer.is_a?(Hash) && !accepted.nil? && !accepted.to_s.empty?

          offer["id"].to_s == accepted.to_s ? offer : nil
        end

        # Free-gift thresholds carry the gift's title, image and value from the first quote, so the
        # form can say what the buyer is working towards ("Add ₹500 more to get <gift> free").
        def with_gift_preview(thresholds, offers, catalog)
          thresholds.map do |threshold|
            next threshold unless threshold["kind"] == "free_gift"

            offer = offers.find { |candidate| candidate.is_a?(Hash) && candidate["id"] == threshold["offer_id"] }
            item = catalog[hash(hash(offer)["config"])["gift_variant_id"].to_s]
            next threshold unless item.is_a?(Hash) && item["available"] != false

            threshold.merge("gift" => { "title" => item["title"].to_s, "image" => item["image"],
                                        "value_cents" => item["unit_price_cents"].to_i })
          end
        end

        def gift_lines(thresholds, offers, catalog, warnings)
          thresholds.filter_map do |threshold|
            next unless threshold["kind"] == "free_gift" && threshold["reached"]

            offer = offers.find { |candidate| candidate.is_a?(Hash) && candidate["id"] == threshold["offer_id"] }
            variant_id = hash(hash(offer)["config"])["gift_variant_id"].to_s
            item = catalog[variant_id]
            unless item.is_a?(Hash) && item["available"] != false
              warnings << "gift_unavailable"
              next
            end
            price = item["unit_price_cents"].to_i
            { "key" => "gift_#{threshold['offer_id']}", "kind" => "gift", "offer_id" => threshold["offer_id"],
              "variant_id" => variant_id, "product_id" => item["product_id"].to_s,
              "collection_ids" => Array(item["collection_ids"]), "title" => item["title"].to_s, "image" => item["image"],
              "quantity" => 1, "original_unit_price_cents" => price, "unit_discount_cents" => price,
              "unit_price_cents" => 0, "compare_at_cents" => price, "line_total_cents" => 0,
              "grams" => item["grams"].to_i, "requires_shipping" => item["requires_shipping"] != false,
              "taxable" => item["taxable"] != false, "properties" => {} }
          end
        end

        def eligibility(input, general, fraud, cart, address, contact, stage)
          reasons = []
          message = nil
          message_key = nil

          # the buyer country is the address country, else the session country; unknown => no country check yet
          country = address["country"].to_s.strip.empty? ? input["country"].to_s.strip : address["country"].to_s.strip
          visibility = Visibility.evaluate(general: general, cart: cart, country: country, page: input["page"])
          visibility["reasons"].delete("country_not_enabled") if country.empty?
          visibility["visible"] = visibility["reasons"].empty?
          unless visibility["visible"]
            reasons.concat(visibility["reasons"])
            message ||= visibility["message"]
            message_key ||= "error_not_eligible"
          end

          rules = CodRules.evaluate(rules: hash(input["rules"]), cart: cart, address: address, contact: contact, stage: stage)
          unless rules["allowed"]
            reasons.concat(rules["reasons"])
            message_key ||= "error_not_eligible"
          end

          block = hash(input["block"])
          if block["blocked"] == true
            reason = block["reason"].to_s.empty? ? "blocked" : block["reason"].to_s
            reasons << reason
            message_key = BLOCK_MESSAGE_KEYS[reason] || "error_blocked"
            custom = block["message"].to_s.strip
            if custom.empty?
              custom = case message_key
                       when "error_limit_reached" then fraud["limit_message"].to_s.strip
                       when "error_max_quantity" then fraud["max_quantity_message"].to_s.strip
                       else fraud["blocked_message"].to_s.strip
                       end
            end
            message = custom unless custom.empty?
          end

          rto = hash(general["rto"])
          risk = input["risk"]
          if rto["gating_enabled"] == true && risk.is_a?(Hash) && rto_blocks?(rto, risk)
            reasons << "rto_high_risk"
            message_key ||= "error_not_eligible"
            text = rto["message"].to_s.strip
            message ||= text unless text.empty?
          end

          reasons.uniq!
          { "cod_allowed" => reasons.empty?, "reasons" => reasons, "message_key" => message_key, "message" => message,
            "pay_online" => hash(general["prepaid"])["show_pay_online"] != false, "pending" => rules["pending"] }
        end

        # What "Pay online" saves (the widget's "Pay online (save upto …)"): the first matching
        # 100 % prepaid rule's discount, plus the COD fee that a prepaid order does not pay.
        def prepaid_offer(input, rule_cart, address, contact, totals, eligibility, fee)
          return nil unless eligibility["pay_online"]

          rule = PartialRules.match(rules: Array(input["prepaid_rules"]), cart: rule_cart, address: address,
                                    contact: contact, risk: input["risk"]).first
          return nil if rule.nil?

          discount = PartialRules.amounts(rule: rule, totals: totals)["discount_cents"].to_i
          return nil unless discount.positive?

          { "rule_id" => rule["id"], "discount_cents" => discount, "save_cents" => discount + fee["amount_cents"].to_i }
        end

        def rto_blocks?(rto, risk)
          block_rank = BAND_RANK[rto["block_band"].to_s.downcase] || BAND_RANK["high"]
          rank = BAND_RANK[risk["band"].to_s.downcase]
          return true if rank && rank >= block_rank

          min_score = rto["min_score"]
          min_score.is_a?(Numeric) && risk["score"].is_a?(Numeric) && risk["score"] >= min_score
        end

        # One order-level discount on a draft order: the discount code and / or the part of the
        # automatic discounts that is not on a line.
        def order_discount(code_input, code_amount, auto_cents, auto_title)
          return nil unless (code_amount + auto_cents).positive?

          code = code_amount.positive? ? code_input["code"].to_s : nil
          title = [code, auto_cents.positive? ? auto_title : nil].compact.join(" + ")
          { "code" => code, "title" => title, "amount_cents" => code_amount + auto_cents,
            "description" => code && !auto_cents.positive? ? nil : title }
        end

        # nil when shipping does not apply to this cart (nothing to re-pick).
        # "fee": {"percent"=>"2.5"} = a percentage of merchandise + shipping, rounded like
        # CodFee; {"cents"=>N} = a fixed amount that the address cannot change.
        def local_pricing(input, shipping_lines, merchandise, currency, free_shipping, fee, tax_added)
          rates = ShippingRates.for_address_estimate(
            rates: Array(input["shipping_rates"]), cart: { "lines" => shipping_lines },
            subtotal_cents: merchandise, currency: currency, free_shipping: free_shipping
          )
          return nil if rates.nil?

          config = hash(input["cod_fee"])
          percentage = fee["enabled"] == true && config["mode"].to_s == "percentage"
          {
            "rates" => rates,
            "hide_single" => input["hide_shipping_selector_when_single"] != false,
            "fee" => percentage ? { "percent" => config["value"].to_s } : { "cents" => fee["amount_cents"].to_i },
            "base_cents" => merchandise,
            "tax_cents" => tax_added
          }
        end

        def tax(config)
          included = config["prices_include_tax"] != false
          return { "status" => "included", "required" => false, "amount_cents" => 0, "lines" => [] } if included

          calculated = config["calculated"]
          if calculated.is_a?(Hash) && calculated["amount_cents"].is_a?(Numeric)
            return { "status" => "calculated", "required" => true, "amount_cents" => [calculated["amount_cents"].round, 0].max,
                     "lines" => Array(calculated["lines"]) }
          end
          { "status" => config["unavailable"] == true ? "unavailable" : "none", "required" => true, "amount_cents" => 0, "lines" => [] }
        end

        def public_line(line)
          { "key" => line["key"], "variant_id" => line["variant_id"].to_s, "product_id" => line["product_id"].to_s,
            "title" => line["title"], "variant_title" => line["variant_title"], "image" => line["image"],
            "quantity" => line["quantity"], "unit_price_cents" => line["unit_price_cents"],
            "compare_at_cents" => line["compare_at_cents"], "line_subtotal_cents" => line["line_subtotal_cents"],
            "discount_cents" => line["discount_cents"] + line["auto_cents"].to_i,
            "discount_title" => line["discount_cents"].positive? ? line["discount_title"] : (line["auto_cents"].to_i.positive? ? line["auto_title"] : nil),
            "line_total_cents" => line["line_total_cents"], "kind" => "product",
            "available" => line["available"], "max_quantity" => line["max_quantity"] }
        end

        def public_extra(line)
          { "key" => line["key"], "kind" => line["kind"], "offer_id" => line["offer_id"], "title" => line["title"],
            "variant_id" => line["variant_id"], "variant_title" => line["variant_title"], "image" => line["image"],
            "quantity" => line["quantity"], "unit_price_cents" => line["unit_price_cents"],
            "compare_at_cents" => line["compare_at_cents"], "line_total_cents" => line["line_total_cents"] }
        end

        def quantity_offer(lines)
          with_offer = lines.select { |line| !line["offer_id"].nil? }
          return nil if with_offer.empty?

          first = with_offer.first
          savings = with_offer.select { |line| line["offer_id"] == first["offer_id"] }.sum do |line|
            (line["unit_discount_cents"].to_i - line["downsell_unit_discount_cents"].to_i - line["bundle_unit_discount_cents"].to_i) * line["quantity"]
          end
          { "offer_id" => first["offer_id"], "applied_tier_index" => first["tier_index"], "savings_cents" => savings }
        end

        def discounts(lines, code_input, code_amount)
          out = []
          tiers = {}
          downsell = nil
          bundles = {}
          lines.each do |line|
            down = line["downsell_unit_discount_cents"].to_i * line["quantity"]
            bundle = line["bundle_unit_discount_cents"].to_i * line["quantity"]
            if bundle.positive?
              entry = bundles[line["bundle_offer_id"]] ||= { "kind" => "bundle", "title" => line["bundle_title"].to_s, "amount_cents" => 0,
                                                             "offer_id" => line["bundle_offer_id"],
                                                             "localized" => line["bundle_title_local"] == true }
              entry["amount_cents"] += bundle
            end
            tier = line["discount_cents"] - down - bundle
            if tier.positive?
              title = line["discount_title"].to_s
              title = title.sub(/ \+ #{Regexp.escape(line['bundle_title'].to_s)}\z/, "") if line["bundle_title"]
              title = title.sub(/ \+ #{Regexp.escape(line['downsell_title'].to_s)}\z/, "") if line["downsell_title"]
              key = [line["offer_id"], title, line["discount_title_local"] == true]
              tiers[key] = tiers[key].to_i + tier
            end
            next unless down.positive?

            downsell ||= { "kind" => "downsell", "title" => line["downsell_title"].to_s, "amount_cents" => 0,
                           "offer_id" => line["downsell_offer_id"], "localized" => line["downsell_title_local"] == true }
            downsell["amount_cents"] += down
          end
          tiers.each do |(offer_id, title, local), amount|
            out << { "kind" => "quantity_offer", "title" => title, "amount_cents" => amount, "offer_id" => offer_id, "localized" => local }
          end
          out << downsell if downsell
          out.concat(bundles.values)
          if code_amount.positive?
            code = code_input["code"].to_s
            out << { "kind" => "discount_code", "title" => code, "amount_cents" => code_amount, "code" => code }
          end
          out
        end

        # Everything DraftOrderBuilder needs; nothing else is read from the quote.
        def draft(currency, lines, extra, code_input, code_amount, selection, shipping_lines, fee, auto_order = 0, auto_title = "")
          auto_title = "Automatic discount" if auto_title.to_s.empty?
          order_extra = auto_order
          draft_lines = lines.map do |line|
            unit_discount = line["unit_discount_cents"].to_i
            percent = line["discount_percent"]
            # A draft line discount is per unit: whole cents per unit go on the line, the few
            # cents that do not divide by the quantity go to the order-level discount.
            auto_unit, auto_left = line["auto_cents"].to_i.divmod(line["quantity"])
            order_extra += auto_left
            if auto_unit.positive?
              own_title = unit_discount.positive? ? line["discount_title"].to_s : ""
              line = line.merge("discount_value_type" => "fixed", "discount_title" => [own_title, auto_title].reject(&:empty?).join(" + "))
              unit_discount += auto_unit
            end
            # PERCENTAGE only when the per-unit amount is exact, so any rounding Shopify applies gives the same total.
            exact_percent = line["discount_value_type"] == "percentage" && percent.is_a?(Numeric) &&
                            (Rational(line["unit_price_cents"]) * Rational(percent.to_s) / 100).denominator == 1
            { "kind" => "product", "key" => line["key"], "variant_id" => line["variant_id"].to_s, "quantity" => line["quantity"],
              "unit_price_cents" => line["unit_price_cents"], "unit_discount_cents" => unit_discount,
              "discount_value_type" => unit_discount.positive? ? (exact_percent ? "percentage" : "fixed") : nil,
              "discount_percent" => unit_discount.positive? && exact_percent ? percent : nil,
              "discount_title" => unit_discount.positive? ? line["discount_title"].to_s : nil,
              "properties" => line["properties"], "requires_shipping" => line["requires_shipping"] != false,
              "taxable" => line["taxable"] != false }
          end
          extra.each do |line|
            custom = line["kind"] == "bump" && line["bump_kind"] == "custom"
            gift = line["kind"] == "gift"
            pre = line["kind"] == PreUpsells::TYPE
            draft_lines << {
              "kind" => gift ? "gift" : (custom ? "custom_bump" : (pre ? PreUpsells::TYPE : "bump")), "key" => line["key"], "offer_id" => line["offer_id"],
              "variant_id" => custom ? nil : line["variant_id"].to_s, "title" => line["title"].to_s, "quantity" => line["quantity"],
              "unit_price_cents" => custom ? line["unit_price_cents"] : line["original_unit_price_cents"],
              "unit_discount_cents" => line["unit_discount_cents"].to_i,
              "discount_value_type" => gift ? "percentage" : (line["unit_discount_cents"].to_i.positive? ? "fixed" : nil),
              "discount_percent" => gift ? 100 : nil,
              "discount_title" => line["unit_discount_cents"].to_i.positive? ? (pre ? line["offer_title"] : line["title"]).to_s : nil,
              "properties" => {}, "requires_shipping" => line["requires_shipping"] == true, "taxable" => line["taxable"] != false
            }
          end

          needs_shipping = shipping_lines.any? { |line| line["requires_shipping"] == true }
          chosen = selection["rates"].find { |rate| rate["id"] == selection["selected_id"] }
          {
            "currency" => currency,
            "lines" => draft_lines,
            "order_discount" => order_discount(code_input, code_amount, order_extra, auto_title),
            "shipping" => needs_shipping && chosen ? { "rate_id" => chosen["id"], "title" => chosen["name"].to_s, "price_cents" => chosen["price_cents"] } : nil,
            "cod_fee" => fee["amount_cents"].positive? ? { "label" => fee["label"], "amount_cents" => fee["amount_cents"], "taxable" => fee["taxable"] } : nil
          }
        end
      end
    end
  end
end
