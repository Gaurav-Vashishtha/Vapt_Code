# frozen_string_literal: true

require "json"
require "set"

unless defined?(::Rails)
  require_relative "money"
end

module CodForm
  module Engine
    # Adapter over the existing PartialRuleSet rules (ARCHITECTURE E.11, PRE-4, PRE-7..9).
    # A rule hash is PartialRuleSet#as_json with string keys (decimals may arrive as strings).
    class PartialRules
      BAND_RANK = { "low" => 0, "medium" => 1, "high" => 2 }.freeze
      DEFAULT_BAND = "high"
      DEFAULT_TEMPLATES = {
        "cod" => "Pay {{total}} on delivery",
        "cod_with_fee" => "Pay {{total}} on delivery ({{cod_fee}} COD fee applicable)",
        "percentage_100" => "Pay {{pay_now}} now (prepaid)",
        "percentage_100_with_discount" => "Pay {{pay_now}} now and get {{discount}} off",
        "percentage" => "Pay {{pay_now}} now and {{pay_later}} on delivery",
        "fixed" => "Pay {{pay_now}} now and {{pay_later}} on delivery",
        "cod_fee_exception" => "Pay {{pay_now}} cod fee now, remaining {{pay_later}} on delivery"
      }.freeze

      class << self
        # cart = {"lines"=>[E.7 lines], "total_cents"=>merchandise total, "total_quantity"=>Integer}
        # => rules that apply, in position order.
        def match(rules:, cart:, address:, contact:, risk:)
          cart = hash(cart)
          lines = Array(cart["lines"]).select { |line| line.is_a?(Hash) }
          total_cents = cart["total_cents"].to_i
          quantity = cart["total_quantity"].is_a?(Numeric) ? cart["total_quantity"].to_i : lines.sum { |l| l["quantity"].to_i }
          zip = hash(address)["zip"].to_s.strip.gsub(/\s+/, "")
          contact = hash(contact)

          ordered(rules).select do |rule|
            next false if rule.key?("is_enabled") && rule["is_enabled"] == false

            cart_range_ok?(rule, total_cents) &&
              product_ok?(rule, lines) &&
              variant_ok?(rule, lines) &&
              collection_ok?(rule, lines) &&
              cart_items_ok?(rule, quantity) &&
              zip_ok?(rule, zip) &&
              !rto_hides?(rule, risk) &&
              !buyer_listed?(rule, contact)
          end
        end

        # rules = the matching rules (output of .match).
        # totals = {"subtotal_cents","line_discount_cents","total_cents","cod_fee_cents"} (see .amounts)
        # => D.2 "payment_options" hash | nil
        def options(rules:, totals:, cod_allowed:, money_format:)
          totals = hash(totals)
          list = ordered(rules)
          offered = list.reject { |rule| kind(rule) == "cod" }
          return nil if offered.empty?

          options = []
          if cod_allowed == true
            total = totals["total_cents"].to_i
            values = { "pay_now_cents" => 0, "pay_later_cents" => total, "discount_cents" => 0 }
            options << {
              "id" => "cod", "kind" => "cod", "title_key" => "payment_full_cod",
              "pay_now_cents" => 0, "pay_later_cents" => total,
              "description" => render(DEFAULT_TEMPLATES["cod"], values, totals, money_format), "rule_id" => nil
            }
          end
          offered.each do |rule|
            values = amounts(rule: rule, totals: totals)
            rule_kind = kind(rule)
            options << {
              "id" => "rule_#{rule['id']}", "kind" => rule_kind,
              "title_key" => rule_kind == "prepaid" ? "payment_prepaid" : "payment_partial",
              "pay_now_cents" => values["pay_now_cents"], "pay_later_cents" => values["pay_later_cents"],
              "description" => description(rule: rule, totals: totals, money_format: money_format),
              "rule_id" => rule["id"], "discount_cents" => values["discount_cents"]
            }
          end
          { "options" => options, "default_id" => options.first["id"] }
        end

        # totals: "subtotal_cents" (lines before any discount), "line_discount_cents" (quantity offer + downsell),
        #         "total_cents" (what the buyer would pay for full COD). Missing keys fall back to total_cents.
        # => {"pay_now_cents","pay_later_cents","discount_cents"}
        def amounts(rule:, totals:)
          totals = hash(totals)
          total = [totals["total_cents"].to_i, 0].max
          return { "pay_now_cents" => 0, "pay_later_cents" => total, "discount_cents" => 0 } if kind(rule) == "cod"

          subtotal = totals.key?("subtotal_cents") ? totals["subtotal_cents"].to_i : total
          base = [subtotal - totals["line_discount_cents"].to_i, 0].max
          discount = [rule_discount(rule, base), total].min
          final = total - discount
          amount = decimal(rule["amount"])

          pay_now =
            if rule["amount_type"].to_s == "percentage"
              amount >= 100 ? final : [Money.percent_of(base, amount), final].min
            else
              [to_cents(amount), final].min
            end
          pay_now = [pay_now, 0].max
          { "pay_now_cents" => pay_now, "pay_later_cents" => [final - pay_now, 0].max, "discount_cents" => discount }
        end

        def description(rule:, totals:, money_format:)
          sub_heading = rule["sub_heading"].to_s.strip
          return sub_heading unless sub_heading.empty?

          template = rule["description_template"].to_s.strip
          template = default_template(rule) if template.empty?
          render(template, amounts(rule: rule, totals: totals), hash(totals), money_format)
        end

        # "cod" | "prepaid" | "partial"
        def kind(rule)
          type = rule["amount_type"].to_s
          return "cod" if type == "cod"
          return "prepaid" if type == "percentage" && decimal(rule["amount"]) == 100

          "partial"
        end

        # rule: the chosen partial/prepaid rule, or nil for a plain prepaid hand-off (Pay online).
        # cart: {"lines"=>[quote lines], "subtotal_cents", "line_discount_cents", "total_cents", "money_format"=>{...}}
        # session: {"public_id","form_id","partial_expand_flow_enabled"}
        # => {"cart_attributes"=>{...D.8...}, "discount_code"=>String|nil}
        def handoff_attributes(rule:, cart:, session:, dummy_variant_id:, otp_phone_e164:, country:)
          cart = hash(cart)
          session = hash(session)
          lines = Array(cart["lines"]).select { |line| line.is_a?(Hash) && !line["variant_id"].to_s.empty? }
          session_id = session["public_id"].to_s

          attributes = { "_codkFormSessionId" => session_id, "_codkFormId" => session["form_id"].to_s }
          unless otp_phone_e164.to_s.strip.empty?
            attributes["_codkSessionId"] = session_id
            attributes["_otpVerifiedPhoneNumber"] = otp_phone_e164.to_s
            attributes["_codkCountryCode"] = country.to_s.upcase
          end

          line_entries = line_discount_entries(lines)
          if rule.nil?
            attributes["_codkDiscounts"] = line_entries.join(",") unless line_entries.empty?
            return { "cart_attributes" => attributes, "discount_code" => nil }
          end

          rule_kind = kind(rule)
          values = amounts(rule: rule, totals: cart)
          code = rule["discount_code"].to_s.strip
          discount_entries = line_entries.dup
          if values["discount_cents"].positive? && !code.empty?
            discount_entries << "orderLevel:#{number(values['discount_cents'])}|#{code}"
          end

          attributes["_codkSessionId"] = session_id
          attributes["_codkCountryCode"] = country.to_s.upcase
          attributes["_codkAmountType"] = rule["amount_type"].to_s
          attributes["_codkAmountValue"] = rule["amount"].to_s
          attributes["_codkCheckoutMode"] = rule_kind == "cod" && truthy?(rule["checkout_cod_only"]) ? "cod_only" : ""
          attributes["_codkFinalDiscountValue"] = ""
          attributes["_codkPrepaidDiscount"] = ""
          attributes["_codkPaymentDescription"] = description(rule: rule, totals: cart, money_format: cart["money_format"])
          attributes["_codkDiscounts"] = discount_entries.join(",")
          attributes["_codkImageURLs"] = image_entries(lines).join(",")
          original = cart.key?("subtotal_cents") ? cart["subtotal_cents"].to_i : cart["total_cents"].to_i
          attributes["_codkOriginalTotal"] = number(original)
          attributes["_partial_product_variant"] = dummy_variant_id.to_s unless dummy_variant_id.to_s.strip.empty?

          case rule_kind
          when "partial"
            ids = lines.map { |line| line["variant_id"].to_s }.select { |id| id.match?(/\A\d+\z/) }.map(&:to_i)
            attributes["partial_payment_variants"] = JSON.generate(ids)
            attributes["_partialPaymentProduct"] = true
            attributes["_codkBundleMode"] = "expand" if session["partial_expand_flow_enabled"] == true
          when "prepaid"
            attributes["partial_payment_variants"] = nil
            attributes["_partialPaymentProduct"] = true
            attributes["_codkDiscounts"] = line_entries.join(",") if decimal(rule["discount_value"]) < 1
            attributes["_codkPrepaidDiscount"] = "#{number(values['discount_cents'])}|#{code}" if values["discount_cents"].positive? && !code.empty?
          end

          applied_code = values["discount_cents"].positive? && !code.empty? ? code : nil
          { "cart_attributes" => attributes, "discount_code" => applied_code }
        end

        private

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def strings(value)
          Array(value).map { |item| item.to_s.strip }.reject(&:empty?)
        end

        def truthy?(value)
          value == true || value.to_s == "true"
        end

        def decimal(value)
          return Rational(value) if value.is_a?(Integer) || value.is_a?(Rational)

          text = value.to_s.strip
          text.match?(/\A-?\d+(\.\d+)?\z/) ? Rational(text) : (value.is_a?(Float) && value.finite? ? Rational(value.to_s) : Rational(0))
        end

        def to_cents(amount)
          (amount * 100 + Rational(1, 2)).floor
        end

        def ordered(rules)
          Array(rules).select { |rule| rule.is_a?(Hash) }.each_with_index.sort_by do |rule, index|
            [rule["position"].to_i, rule["id"].is_a?(Integer) ? rule["id"] : 0, index]
          end.map(&:first)
        end

        def scope(value)
          text = value.to_s.strip
          text.empty? ? "all" : text
        end

        def cart_range_ok?(rule, total_cents)
          min = decimal(rule["min_cart_range"])
          max = decimal(rule["max_cart_range"])
          total = Rational(total_cents, 100)
          return false if min.positive? && total < min
          return false if max.positive? && total > max

          true
        end

        def product_ok?(rule, lines)
          ids = strings(rule["product_ids"])
          cart_ids = lines.map { |line| line["product_id"].to_s }.reject(&:empty?)
          case scope(rule["product_scope"])
          when "include"
            return false if cart_ids.empty?

            truthy?(rule["match_any_product"]) ? cart_ids.any? { |id| ids.include?(id) } : cart_ids.all? { |id| ids.include?(id) }
          when "exclude" then cart_ids.none? { |id| ids.include?(id) }
          else true
          end
        end

        # Same as PartialRuleSet#variant_matches?
        def variant_ok?(rule, lines)
          variant_scope = scope(rule["variant_scope"])
          ids = strings(rule["variant_ids"])
          return true if variant_scope == "all" || ids.empty?

          cart_ids = lines.map { |line| line["variant_id"].to_s }.reject(&:empty?)
          return variant_scope == "exclude" if cart_ids.empty?

          case variant_scope
          when "include"
            truthy?(rule["match_any_product"]) ? cart_ids.any? { |id| ids.include?(id) } : cart_ids.all? { |id| ids.include?(id) }
          when "exclude" then cart_ids.none? { |id| ids.include?(id) }
          else true
          end
        end

        # Same as PartialRuleSet#collection_matches?
        def collection_ok?(rule, lines)
          collection_scope = scope(rule["collection_scope"])
          ids = strings(rule["collection_ids"]).to_set
          return true if collection_scope == "all" || ids.empty?

          products = lines.reject { |line| line["product_id"].to_s.empty? }.map { |line| strings(line["collection_ids"]) }
          return collection_scope == "exclude" if products.empty?

          matcher = ->(collections) { collections.any? { |id| ids.include?(id) } }
          case collection_scope
          when "include" then truthy?(rule["match_any_product"]) ? products.any?(&matcher) : products.all?(&matcher)
          when "exclude" then products.none?(&matcher)
          else true
          end
        end

        def cart_items_ok?(rule, quantity)
          range = rule["cart_items_range"]
          return true unless range.is_a?(Hash)

          min = Integer(range["min_cart_items"].to_s.strip, exception: false)
          max = Integer(range["max_cart_items"].to_s.strip, exception: false)
          return false if min && quantity < min
          return false if max && quantity > max

          true
        end

        # Same as zipcode_blacklisted? / zipcode_whitelisted?; skipped while the zip is empty.
        def zip_ok?(rule, zip)
          return true if zip.empty?
          return false if truthy?(rule["zipcode_blacklist_enabled"]) && zip_listed?(rule["zipcode_blacklist"], zip)

          if truthy?(rule["zipcode_whitelist_enabled"])
            entries = zip_entries(rule["zipcode_whitelist"])
            return false unless entries.empty? || zip_listed?(rule["zipcode_whitelist"], zip)
          end
          true
        end

        def zip_entries(list)
          list.to_s.split(",").map(&:strip).reject(&:empty?)
        end

        def zip_listed?(list, zip)
          zip_entries(list).any? do |entry|
            if entry.include?("-")
              from, to = entry.split("-").map(&:strip)
              !from.nil? && !to.nil? && zip >= from && zip <= to
            else
              zip == entry
            end
          end
        end

        # Same as PartialRuleSet#rto_engine_hides?
        def rto_hides?(rule, risk)
          config = rule["rto_engine"]
          return false unless config.is_a?(Hash) && truthy?(config["enabled"]) && risk.is_a?(Hash)

          hide_at = config["hide_at_band"].to_s.downcase
          hide_at = DEFAULT_BAND unless BAND_RANK.key?(hide_at)
          rank = BAND_RANK[risk["band"].to_s.downcase]
          return true if rank && rank >= BAND_RANK[hide_at]

          raw = config["min_score"]
          return false if raw.nil? || raw.to_s.strip.empty? || risk["score"].nil?

          risk["score"].to_i >= [[raw.to_i, 0].max, 100].min
        end

        def buyer_listed?(rule, contact)
          candidates = [contact["phone_digits"], contact["phone_national"]].map do |value|
            value.to_s.gsub(/\D/, "").sub(/\A0+/, "")
          end.reject(&:empty?)
          phones = strings(rule["phone_blacklist"]).map { |entry| entry.gsub(/\D/, "").sub(/\A0+/, "") }.reject(&:empty?)
          return true if candidates.any? { |candidate| phones.include?(candidate) }

          email = contact["email"].to_s.strip.downcase
          !email.empty? && strings(rule["email_blacklist"]).map(&:downcase).include?(email)
        end

        # Rule discount applies only with a discount code: percentage of (original total - line discounts), or fixed.
        def rule_discount(rule, base)
          value = decimal(rule["discount_value"])
          return 0 if !value.positive? || rule["discount_code"].to_s.strip.empty?

          rule["discount_type"].to_s == "percentage" ? Money.percent_of(base, value) : to_cents(value)
        end

        # Same choice as PartialRuleSet#default_template.
        def default_template(rule)
          type = rule["amount_type"].to_s
          amount = decimal(rule["amount"])
          shown = rule["amount_to_show"].to_s.strip
          if type == "cod"
            fee = shown.empty? ? amount : decimal(shown)
            fee.positive? ? DEFAULT_TEMPLATES["cod_with_fee"] : DEFAULT_TEMPLATES["cod"]
          elsif type == "percentage" && amount == 100 then DEFAULT_TEMPLATES["percentage_100"]
          elsif type == "percentage" then DEFAULT_TEMPLATES["percentage"]
          elsif type == "fixed" && amount.zero? && !shown.empty? then DEFAULT_TEMPLATES["cod_fee_exception"]
          else DEFAULT_TEMPLATES["fixed"]
          end
        end

        def render(template, values, totals, money_format)
          total_after = values["pay_now_cents"].to_i + values["pay_later_cents"].to_i
          map = {
            "pay_now" => values["pay_now_cents"], "pay_later" => values["pay_later_cents"],
            "total" => total_after, "discount" => values["discount_cents"], "cod_fee" => totals["cod_fee_cents"].to_i
          }
          template.to_s.gsub(/\{\{\s*(pay_now|pay_later|total|discount|cod_fee)\s*\}\}/) do
            Money.format(map[Regexp.last_match(1)].to_i, money_format)
          end
        end

        # "<variantId>:<line discount>|<title>" (F34), amounts as plain decimals.
        def line_discount_entries(lines)
          grouped = {}
          lines.each do |line|
            discount = line["discount_cents"].is_a?(Numeric) ? line["discount_cents"].to_i : line["unit_discount_cents"].to_i * line["quantity"].to_i
            next unless discount.positive?

            entry = (grouped[line["variant_id"].to_s] ||= { "amount" => 0, "title" => "" })
            entry["amount"] += discount
            entry["title"] = line["discount_title"].to_s if entry["title"].empty?
          end
          grouped.map do |variant_id, entry|
            title = entry["title"].gsub(/[,|]/, " ").strip
            title.empty? ? "#{variant_id}:#{number(entry['amount'])}" : "#{variant_id}:#{number(entry['amount'])}|#{title}"
          end
        end

        def image_entries(lines)
          seen = {}
          lines.filter_map do |line|
            variant_id = line["variant_id"].to_s
            image = line["image"].to_s
            next if image.empty? || seen[variant_id]

            seen[variant_id] = true
            "#{variant_id}:#{encode(image)}"
          end
        end

        # JS encodeURIComponent
        def encode(text)
          text.to_s.b.gsub(/[^A-Za-z0-9\-_.!~*'()]/n) { |char| Kernel.format("%%%02X", char.ord) }
        end

        # 50000 => "500", 1250 => "12.5"  (how JS prints the same number)
        def number(cents)
          value = cents.to_i
          text = Money.to_decimal_string(value)
          text.sub(/\.?0+\z/, "")
        end
      end
    end
  end
end
