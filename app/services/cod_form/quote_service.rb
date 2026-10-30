# frozen_string_literal: true

module CodForm
  # Server-side quote: assembles the CodForm::Engine::Quote input from Shopify, Setting and the
  # form tables, never from client prices (ARCHITECTURE.md F.1, D.2, ORD-2).
  #
  #   CodForm::QuoteService.call(shop:, config:, session:, params:, stage:)   # => public quote (D.2)
  #   CodForm::QuoteService.build(...)                                        # => Result (incl. internal keys)
  class QuoteService
    Result = Struct.new(:quote, :public_quote, :lines, :offers, :contact, :address, :currency, :schema,
                        :phone, :block, :items, :money_format, :general, :fraud, keyword_init: true)

    ADDRESS_KEYS = %w[country province city zip address1 address2].freeze
    CONTACT_KEYS = %w[first_name last_name phone email].freeze
    MAX_FIELD_LENGTH = 255
    CONFIRMED_KEY = "confirmed_total"
    AUTOMATIC_KEY = "automatic_discounts"

    class << self
      def call(shop:, config:, session:, params:, stage: "quote", **options)
        build(shop: shop, config: config, session: session, params: params, stage: stage, **options).public_quote
      end

      # params (string keys): items, address, contact, shipping_rate_id, bumps, pre_upsells, discount_code,
      # downsell_offer_id, want_tax. options: ip:, timing: (submit only), persist: (default true),
      # force_tax: (submit), meta: (draft meta for the tax call).
      def build(shop:, config:, session:, params:, stage: "quote", ip: nil, timing: nil, persist: true, force_tax: false)
        params = params.is_a?(Hash) ? params : {}
        setting = shop.setting
        general = general_settings(config)
        fraud = fraud_settings(config)
        flags = CodForm::Gates.flags(shop, config: config)
        general = apply_gates(general, flags)
        shop_info = CodForm::CatalogService.shop_info(shop)

        address = clean_address(params["address"], session)
        country = address["country"]
        items = params["items"].is_a?(Array) ? params["items"] : Array(session.cart_snapshot.is_a?(Hash) ? session.cart_snapshot["items"] : nil)
        lines = CodForm::CatalogService.lines(shop, items, country: country)
        clean_items = lines.map { |l| { "variant_id" => l["variant_id"], "quantity" => l["quantity"], "properties" => l["properties"] } }
        currency = (lines.first && lines.first["currency"]).to_s.presence || session.currency.to_s.presence || shop_info["currency"].to_s

        schema = CodForm::CatalogService.country_schema(country)
        phone = phone_result(params, session, country)
        contact = engine_contact(params, session, phone)

        resolved = CodForm::OfferResolver.call(
          shop: shop, lines: lines, client_id: session.client_id.presence || session.public_id,
          assignments: session.ab_assignments, flags: flags, country: country
        )
        offers = resolved.offers
        downsell_id = params["downsell_offer_id"]
        offers, downsell_id = apply_recovery_discount(offers, downsell_id, session, general)

        merch_estimate = lines.sum { |l| l["unit_price_cents"].to_i * l["quantity"].to_i }
        partial_rules = CodForm::PartialRulesAdapter.for(shop)
        risk = risk_for(shop, general, setting, flags, partial_rules, phone, contact, address, merch_estimate)
        block = block_for(shop, config, session, contact, ip, lines, fraud, flags, timing: nil)

        money_format = CodForm::MoneyFormatAdapter.for(shop, currency: currency, shop_info: shop_info)
        # Only a HINT for the time before the address is known. Neither Shopify's shop-level
        # "prices include tax" flag nor Setting#is_tax_included_with_product reliably predicts
        # what a draft order totals (markets, tax overrides), so as soon as the address is
        # complete the tax is confirmed with Shopify itself (see below). Trusting the flags made
        # the form show a tax-free total that Shopify then raised at order creation
        # (409 total_changed on every first submit).
        prices_include_tax = shop_info["taxes_included"] == true

        input = {
          "currency" => currency,
          "stage" => stage.to_s,
          "page" => session.source.to_s == "recovery" ? "api" : session.source.to_s,
          "locale" => session.locale,
          "lines" => lines,
          "address" => address.slice("country", "province", "city", "zip"),
          "contact" => contact,
          "general" => general,
          "fraud" => fraud,
          "rules" => CodForm::RulesAdapter.from_setting(setting),
          "shipping_rates" => CodForm::ShippingRate.where(shop_id: shop.id).active.ordered.map(&:to_engine_hash),
          "selected_shipping_rate_id" => integer_or_nil(params["shipping_rate_id"]),
          "hide_shipping_selector_when_single" => form_design(session)["hide_shipping_selector_when_single"] != false,
          "offers" => offers,
          "selected_bumps" => selected_bumps(params["bumps"]),
          "selected_pre_upsells" => selected_pre_upsells(params["pre_upsells"]),
          "bump_catalog" => resolved.bump_catalog,
          "downsell_offer_id" => downsell_id,
          "discount_code" => discount_code(shop, session, params["discount_code"], general, flags, currency),
          "cod_fee" => CodForm::CodFeeAdapter.from_setting(setting, currency: currency, shop_currency: shop_info["currency"], general: general),
          "tax" => { "prices_include_tax" => prices_include_tax, "calculated" => nil },
          "partial_rules" => partial_rules,
          "risk" => risk,
          "otp" => {
            "shop_enabled" => CodForm::OtpService.enabled_for?(setting, session.form&.published_config, general),
            "mode" => general.dig("otp", "mode").to_s,
            "risk_band" => general.dig("otp", "risk_band").to_s,
            "verified" => otp_verified_for?(session, phone)
          },
          "block" => block,
          "money_format" => money_format,
          "is_test" => session.is_test ? true : false
        }

        quote = CodForm::Engine::Quote.build(input)

        # ORD-3: with a complete address Shopify calculates the very draft order the submit will
        # create, and its total is the truth (cached 10 min per cart + destination, so repeated
        # quotes cost nothing). `quote` here carries no tax yet, whatever the hint said.
        complete = tax_address_complete?(address, schema)

        # The store's own automatic discounts, as Shopify applies them to these products. Before
        # the address is complete this runs only for shops known to have such discounts (see
        # automatic_discounts_expected?), so other shops pay no extra Shopify call at open.
        # A session that once got such a discount keeps asking (the mark lives on the session,
        # so it does not depend on the cache store).
        automatic_session = session.cart_snapshot.is_a?(Hash) && session.cart_snapshot[AUTOMATIC_KEY] == true
        if complete || automatic_session || automatic_discounts_expected?(shop)
          automatic = CodForm::AutomaticDiscountService.calculate(shop, quote, country)
          if automatic.is_a?(Hash) && automatic["amount_cents"].to_i.positive?
            automatic_session = true
            remember_automatic_discounts(shop)
            input["automatic_discount"] = automatic
            quote = CodForm::Engine::Quote.build(input)
          end
        end

        if complete
          calculated = calculate_tax(shop, quote, address, country)
          input["tax"] = verified_tax(prices_include_tax, calculated, quote["total_cents"].to_i)
          quote = CodForm::Engine::Quote.build(input)
        end

        quote = apply_confirmed_total(session, quote, address)
        public_quote = strip_internal(quote)
        persist_snapshot(session, public_quote, clean_items, risk, automatic_session) if persist

        Result.new(
          quote: quote, public_quote: public_quote, lines: lines, offers: resolved, contact: contact, address: address,
          currency: currency, schema: schema, phone: phone, block: block, items: clean_items,
          money_format: money_format, general: general, fraud: fraud
        )
      end

      AUTOMATIC_SEEN_TTL = 1.day

      def automatic_seen_key(shop)
        "codf:autodisc:seen:#{shop.id}"
      end

      # True once Shopify applied an automatic discount to any form cart of this shop, or the
      # storefront cart showed discounted line prices (Api::Form::SessionsController).
      def automatic_discounts_expected?(shop)
        CodForm::Cache.store.read(automatic_seen_key(shop)) == true
      end

      def remember_automatic_discounts(shop)
        CodForm::Cache.store.write(automatic_seen_key(shop), true, expires_in: AUTOMATIC_SEEN_TTL)
      end

      # QuoteService strips every key starting with "_" before a quote leaves the server.
      def strip_internal(quote)
        quote.reject { |key, _| key.to_s.start_with?("_") }
      end

      # After Shopify answered a draft order with another total than ours (rounding, or tax we
      # could not calculate), that total is remembered for exactly this cart and destination.
      # Returns the public quote carrying Shopify's total.
      def confirm_total!(session, quote, address, shopify_total_cents)
        return strip_internal(quote) unless shopify_total_cents.is_a?(Integer)

        snapshot = session.cart_snapshot.is_a?(Hash) ? session.cart_snapshot : {}
        snapshot = snapshot.merge(CONFIRMED_KEY => { "fingerprint" => total_fingerprint(quote, address), "total_cents" => shopify_total_cents })
        session.update_columns(cart_snapshot: snapshot, updated_at: Time.current)
        strip_internal(apply_confirmed_total(session, quote, address))
      end

      def apply_confirmed_total(session, quote, address)
        confirmed = session.cart_snapshot.is_a?(Hash) ? session.cart_snapshot[CONFIRMED_KEY] : nil
        return quote unless confirmed.is_a?(Hash) && confirmed["total_cents"].is_a?(Integer)
        return quote unless confirmed["fingerprint"] == total_fingerprint(quote, address)

        delta = confirmed["total_cents"] - quote["total_cents"].to_i
        return quote if delta.zero?

        adjusted = quote.merge("total_cents" => confirmed["total_cents"])
        tax = quote["tax"].is_a?(Hash) ? quote["tax"] : {}
        # Without a tax figure of our own, the difference is the tax Shopify added.
        if tax["required"] == true && tax["status"] != "calculated" && delta.positive?
          adjusted["tax"] = tax.merge("status" => "calculated", "amount_cents" => delta)
        end
        adjusted
      end

      # Cart (lines, discounts, shipping, fee, our total) + tax destination.
      def total_fingerprint(quote, address)
        Digest::SHA256.hexdigest([quote["_fingerprint"], address["country"], address["province"], address["zip"]].join("|"))
      end

      # cod_form_shop_configs.general / .fraud merged over the defaults (rows start as {}).
      def general_settings(config)
        deep_merge(CodForm::Engine::Defaults.general, config.general.is_a?(Hash) ? config.general : {})
      end

      def fraud_settings(config)
        deep_merge(CodForm::Engine::Defaults.fraud, config.fraud.is_a?(Hash) ? config.fraud : {})
      end

      def deep_merge(base, override)
        base.merge(override) do |_key, left, right|
          left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
        end
      end

      # OTP counts only for the phone it was verified with: a session that verified one number
      # and then quotes or submits another one needs OTP again (D.5).
      def otp_verified_for?(session, phone)
        return false unless session.otp_verified_at.present? && phone.is_a?(Hash) && phone["valid"] == true

        verified_digits = session.otp.is_a?(Hash) ? session.otp["verified_digits"].to_s : ""
        verified_digits = session.phone_normalized.to_s if verified_digits.empty?
        !verified_digits.empty? && verified_digits == phone["digits"].to_s
      end

      # Small, PII-free metadata for server-written funnel events.
      def funnel_meta(session)
        {
          "country" => session.country_code, "device" => session.device, "source" => session.source,
          "form_id" => session.cod_form_id, "test" => session.is_test ? true : false
        }.compact
      end

      # {"country","province","city","zip","address1","address2"}; country falls back to the session's.
      def clean_address(raw, session)
        raw = raw.is_a?(Hash) ? raw : {}
        stored = session.address.is_a?(Hash) ? session.address : {}
        out = ADDRESS_KEYS.to_h { |key| [key, limit(raw.key?(key) ? raw[key] : stored[key])] }
        out["country"] = out["country"].upcase
        out["country"] = session.country_code.to_s.upcase unless out["country"].match?(/\A[A-Z]{2}\z/)
        out["province"] = out["province"].sub(/\A#{Regexp.escape(out['country'])}-(?=.)/i, "") unless out["country"] == "PE"
        out
      end

      def limit(value)
        value.is_a?(String) || value.is_a?(Numeric) ? value.to_s.strip[0, MAX_FIELD_LENGTH] : ""
      end

      # CodForm::Engine::Phone.validate result for the submitted (or stored) phone.
      def phone_result(params, session, country)
        raw = params["contact"].is_a?(Hash) ? params["contact"]["phone"] : nil
        if raw.to_s.strip.empty?
          stored = session.contact.is_a?(Hash) ? session.contact : {}
          raw = stored["phone_e164"].presence || stored["phone_national"]
        end
        CodForm::Engine::Phone.validate(
          raw: raw.to_s[0, 40], country: country,
          rules: CodForm::Engine::CountrySchema.phone_rules(country: country)
        )
      end

      def engine_contact(params, session, phone)
        raw = params["contact"].is_a?(Hash) ? params["contact"] : {}
        stored = session.contact.is_a?(Hash) ? session.contact : {}
        email = (raw.key?("email") ? raw["email"] : stored["email"]).to_s.strip.downcase[0, MAX_FIELD_LENGTH]
        valid = phone.is_a?(Hash) && phone["valid"] == true
        {
          "phone_digits" => valid ? phone["digits"].to_s : "",
          "phone_national" => valid ? phone["national"].to_s : "",
          "email" => email
        }
      end

      private

      # A gated-off feature is simply absent (J.1).
      def apply_gates(general, flags)
        out = general.dup
        out["rto"] = out["rto"].merge("gating_enabled" => false) unless flags["rto_gating"] == true
        out["otp"] = out["otp"].merge("mode" => "before_order") if out.dig("otp", "mode") == "risk_based" && flags["risk_based_otp"] != true
        out["discounts"] = out["discounts"].merge("code_field_enabled" => false) unless flags["discount_code_field"] == true
        out
      end

      def form_design(session)
        form = session.cod_form_id ? CodForm::Form.find_by(id: session.cod_form_id, shop_id: session.shop_id) : nil
        design = form&.published_config.is_a?(Hash) ? form.published_config["design"] : nil
        design.is_a?(Hash) ? design : {}
      end

      def integer_or_nil(value)
        Integer(value.to_s, exception: false)
      end

      # [{"offer_id","variant_id","quantity"}] the buyer added from the pre-purchase upsell popup.
      def selected_pre_upsells(raw)
        Array(raw).first(CodForm::Engine::PreUpsells::MAX_PRODUCTS).filter_map do |choice|
          next unless choice.is_a?(Hash)

          id = integer_or_nil(choice["offer_id"])
          variant_id = choice["variant_id"].to_s
          next unless id && variant_id.match?(/\A\d{1,20}\z/)

          quantity = integer_or_nil(choice["quantity"]) || 1
          { "offer_id" => id, "variant_id" => variant_id,
            "quantity" => quantity.clamp(1, CodForm::Engine::PreUpsells::MAX_QUANTITY) }
        end
      end

      def selected_bumps(raw)
        Array(raw).first(10).filter_map do |bump|
          next unless bump.is_a?(Hash)

          id = integer_or_nil(bump["offer_id"])
          id ? { "offer_id" => id, "quantity" => [integer_or_nil(bump["quantity"]) || 1, 1].max } : nil
        end
      end

      def discount_code(shop, session, code, general, flags, currency)
        code = code.to_s.strip
        return nil if code.empty?
        return { "code" => code[0, 64], "error" => "disabled" } unless general.dig("discounts", "code_field_enabled") == true && flags["discount_code_field"] == true

        limit, period = CodForm::RateLimiter.default_limit("discount_code")
        unless CodForm::RateLimiter.hit!("codf:disc:#{session.public_id}", limit: limit, period: period)
          return { "code" => code[0, 64], "error" => "rate_limited" }
        end

        found = CodForm::DiscountCodeService.lookup(shop, code)
        # A fixed amount / minimum in another currency than the quote cannot be applied exactly.
        if found["error"].nil? && found["currency"].present? && found["currency"].to_s.upcase != currency.to_s.upcase
          return { "code" => found["code"], "error" => "unsupported" }
        end
        found
      end

      # ABN-2: the optional recovery discount is applied as a downsell-type discount on a
      # recovery session, unless the buyer accepted a real downsell.
      def apply_recovery_discount(offers, downsell_id, session, general)
        return [offers, downsell_id] unless session.source.to_s == "recovery" && downsell_id.to_s.empty?

        discount = general.dig("abandonment", "recovery_discount")
        return [offers, downsell_id] unless discount.is_a?(Hash) && %w[percentage fixed_amount].include?(discount["type"].to_s) && discount["value"].to_f.positive?

        synthetic = {
          "id" => "recovery", "offer_type" => "downsell", "status" => "active", "priority" => 0,
          "targeting" => { "scope" => "all" },
          "config" => { "discount_type" => discount["type"].to_s, "value" => discount["value"], "title" => { "default" => "Welcome back" } }
        }
        [offers.merge("downsell" => synthetic), "recovery"]
      end

      # Only when RTO gating or risk-based OTP is on (and gated in), once phone and zip are known.
      def risk_for(shop, general, setting, flags, partial_rules, phone, contact, address, total_cents)
        gating = general.dig("rto", "gating_enabled") == true && flags["rto_gating"] == true
        risk_otp = general.dig("otp", "mode") == "risk_based" && flags["risk_based_otp"] == true && CodForm::OtpService.on?(setting, general)
        # ... or when an enabled partial rule hides itself by RTO band (E.11 `rto_engine`).
        partial_rto = partial_rules.any? { |rule| rule["rto_engine"].is_a?(Hash) && [true, "true"].include?(rule["rto_engine"]["enabled"]) }
        return nil unless gating || risk_otp || partial_rto
        return nil unless phone["valid"] == true && !address["zip"].empty?

        CodForm::RiskService.call(
          shop: shop, phone: phone["e164"], email: contact["email"], zip: address["zip"],
          country: address["country"], total_cents: total_cents
        )
      end

      def block_for(shop, config, session, contact, ip, lines, fraud, flags, timing:)
        result = CodForm::FraudAdapter.check(
          shop: shop, config: config, contact: contact, ip: ip.presence || session.ip, cart: { "lines" => lines },
          timing: timing, is_test: session.is_test, flags: flags, fraud: fraud
        )
        { "blocked" => result["ok"] != true, "reason" => result["reason"], "message" => result["message"], "code" => result["code"] }
      end

      # Engine tax config from Shopify's calculation. What Shopify charges ON TOP of our pre-tax
      # total is the tax line (zero or less: the prices already include it). Using the difference
      # rather than Shopify's totalTax keeps "shown total == order total" for inclusive shops too.
      def verified_tax(hint_included, calculated, pre_tax_total_cents)
        if calculated.nil?
          return { "prices_include_tax" => true, "calculated" => nil } if hint_included

          return { "prices_include_tax" => false, "calculated" => nil, "unavailable" => true }
        end

        shopify_total = calculated["total_cents"]
        on_top = if shopify_total.is_a?(Numeric)
                   shopify_total.round - pre_tax_total_cents
                 else
                   hint_included ? 0 : calculated["amount_cents"].to_i
                 end
        return { "prices_include_tax" => true, "calculated" => nil } unless on_top.positive?

        { "prices_include_tax" => false, "calculated" => calculated.merge("amount_cents" => on_top), "unavailable" => false }
      end

      def tax_address_complete?(address, schema)
        return false if address["country"].empty?

        rules = schema["address"].is_a?(Hash) ? schema["address"] : {}
        province_needed = rules.dig("province", "mode").to_s == "select" && rules.dig("province", "required") != false
        zip_needed = rules.dig("zip", "required") == true
        (!province_needed || !address["province"].empty?) && (!zip_needed || !address["zip"].empty?)
      end

      # Tax needs only prices and the destination: the draft input is built without contact data.
      def calculate_tax(shop, quote, address, country)
        draft_input = CodForm::Engine::DraftOrderBuilder.build(
          quote: quote, contact: {},
          address: CodForm::OrderService.draft_address(address).slice("country", "province", "city", "zip"),
          meta: { "country" => country, "session_id" => "", "form_id" => "" }
        )
        draft_input = draft_input.slice("lineItems", "appliedDiscount", "shippingLine", "shippingAddress", "presentmentCurrencyCode", "taxExempt", "acceptAutomaticDiscounts")
        CodForm::TaxService.calculate(shop, draft_input)
      rescue StandardError => e
        Rails.logger.warn("[CodForm::QuoteService] tax failed shop_id=#{shop.id} #{e.class}")
        nil
      end

      def persist_snapshot(session, public_quote, items, risk, automatic = false)
        previous = session.cart_snapshot.is_a?(Hash) ? session.cart_snapshot.slice(CONFIRMED_KEY) : {}
        previous[AUTOMATIC_KEY] = true if automatic
        attrs = {
          quote_snapshot: public_quote,
          cart_snapshot: previous.merge("items" => items, "source" => session.source),
          updated_at: Time.current
        }
        attrs[:currency] = public_quote["currency"] if public_quote["currency"].present?
        attrs[:risk] = risk if risk.is_a?(Hash)
        session.update_columns(attrs)
      end
    end
  end
end
