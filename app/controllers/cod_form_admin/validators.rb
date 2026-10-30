# frozen_string_literal: true

require "json"
require "time"
require "ipaddr"

module CodFormAdmin
  # Pure validation / normalisation of the admin API payloads that have no engine normaliser
  # (ARCHITECTURE.md B.1.1, B.1.2, C.3, C.4, C.5, C.6, B.6). Form and button configs are
  # normalised by CodForm::Engine::FormConfig / ButtonConfig (WS2); only a structural pre-check
  # for forms lives here.
  #
  # Plain Ruby, stdlib only, string keys in and out, so the tests run without Rails:
  #   ruby test/controllers/cod_form_admin/validators_test.rb
  #
  # Every `normalize` returns {"value" => Hash, "errors" => {"<path>" => ["message"]}, "warnings" => [..]}.
  # Unknown keys are dropped; a known key with a wrong type is an error (never silently defaulted).
  module Validators
    MAX_ID_LIST = 2_000
    MAX_TEXT = 300
    LOCALE_RE = /\A[a-z]{2,3}(-[A-Za-z0-9]{2,8})?\z/.freeze
    COUNTRY_RE = /\A[A-Z]{2}\z/.freeze
    MAX_LOCALES = 12

    # Small typed-coercion toolbox shared by the validators below.
    module Util
      module_function

      def errors
        Hash.new { |hash, key| hash[key] = [] }
      end

      def result(value, errs, warnings = [])
        { "value" => value, "errors" => errs.reject { |_, list| list.empty? }, "warnings" => warnings }
      end

      def hash(value)
        value.is_a?(Hash) ? value : {}
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
      end

      def deep_dup(value)
        case value
        when Hash then value.each_with_object({}) { |(k, v), out| out[k.to_s] = deep_dup(v) }
        when Array then value.map { |v| deep_dup(v) }
        else value
        end
      end

      def deep_merge(base, over)
        return deep_dup(over) unless base.is_a?(Hash) && over.is_a?(Hash)

        out = deep_dup(base)
        over.each { |key, value| out[key.to_s] = out.key?(key.to_s) ? deep_merge(out[key.to_s], value) : deep_dup(value) }
        out
      end

      def bool(value, path, errs, fallback)
        return value if [true, false].include?(value)

        errs[path] << "must be true or false"
        fallback
      end

      # Integer, an integral Float (JSON 10.0) or a digit string. nil when it is not a whole number.
      def to_int(value)
        case value
        when Integer then value
        when Float then value.finite? && value == value.to_i ? value.to_i : nil
        when String then value.strip.match?(/\A-?\d{1,15}\z/) ? value.strip.to_i : nil
        end
      end

      def int(value, path, errs, fallback, min: nil, max: nil)
        number = to_int(value)
        if number.nil?
          errs[path] << "must be a whole number"
          return fallback
        end
        if (min && number < min) || (max && number > max)
          errs[path] << range_message(min, max)
          return fallback
        end
        number
      end

      def int_or_nil(value, path, errs, fallback, min: nil, max: nil)
        return nil if value.nil? || value == ""

        int(value, path, errs, fallback, min: min, max: max)
      end

      def number(value, path, errs, fallback, min: nil, max: nil)
        unless value.is_a?(Numeric) && (!value.is_a?(Float) || value.finite?)
          errs[path] << "must be a number"
          return fallback
        end
        if (min && value < min) || (max && value > max)
          errs[path] << range_message(min, max)
          return fallback
        end
        value
      end

      def range_message(min, max)
        return "must be between #{min} and #{max}" if min && max
        return "must be at least #{min}" if min

        "must be at most #{max}"
      end

      def enum(value, path, errs, fallback, allowed)
        return value if allowed.include?(value)

        errs[path] << "must be one of: #{allowed.map { |v| v.nil? ? 'null' : v }.join(', ')}"
        fallback
      end

      def string(value, path, errs, fallback, max: MAX_TEXT, required: false)
        value = "" if value.nil? && !required
        unless value.is_a?(String)
          errs[path] << "must be text"
          return fallback
        end
        text = value.strip
        errs[path] << "is required" if required && text.empty?
        if text.length > max
          errs[path] << "is too long (maximum #{max} characters)"
          return fallback
        end
        text
      end

      # CSS selector typed by the merchant: same rule as Engine::ButtonConfig (max 200, no < > { }).
      def selector(value, path, errs, fallback)
        text = string(value, path, errs, fallback, max: 200)
        if text.is_a?(String) && text.match?(/[<>{}]/)
          errs[path] << "must not contain < > { }"
          return fallback
        end
        text
      end

      def url(value, path, errs, fallback, max: 2_000)
        text = string(value, path, errs, fallback, max: max)
        return text if !text.is_a?(String) || text.empty?
        return text if text.match?(%r{\Ahttps://[^\s<>"']+\z})

        errs[path] << "must be an https URL"
        fallback
      end

      # Shopify ids as numeric strings (0.1). Accepts integers, digit strings and gid://shopify/X/123.
      def shopify_id(value)
        text = value.is_a?(Integer) ? value.to_s : value.to_s.strip
        text = text.split("/").last.to_s if text.start_with?("gid://")
        text.match?(/\A\d{1,20}\z/) ? text : nil
      end

      def id_list(value, path, errs, fallback, max: MAX_ID_LIST)
        unless value.is_a?(Array)
          errs[path] << "must be a list of ids"
          return fallback
        end
        ids = value.map { |entry| shopify_id(entry) }
        if ids.any?(&:nil?)
          errs[path] << "must contain only numeric Shopify ids"
          return fallback
        end
        ids = ids.uniq
        if ids.size > max
          errs[path] << "is too long (maximum #{max} ids)"
          return fallback
        end
        ids
      end

      def id_or_nil(value, path, errs, fallback)
        return nil if value.nil? || value == ""

        id = shopify_id(value)
        return id if id

        errs[path] << "must be a numeric Shopify id"
        fallback
      end

      def countries(value, path, errs, fallback)
        unless value.is_a?(Array)
          errs[path] << "must be a list of country codes"
          return fallback
        end
        codes = value.map { |code| code.to_s.strip.upcase }.uniq
        unless codes.all? { |code| code.match?(COUNTRY_RE) }
          errs[path] << "must contain only ISO 3166-1 alpha-2 country codes"
          return fallback
        end
        codes
      end

      # {locale => string}. `default` is mandatory when require_default is true (C.1.2).
      def localized(value, path, errs, fallback, max: MAX_TEXT, require_default: true)
        value = { "default" => value } if value.is_a?(String)
        unless value.is_a?(Hash)
          errs[path] << "must be an object of locale => text"
          return fallback
        end
        out = {}
        value.each do |locale, text|
          key = locale.to_s
          unless key == "default" || key.match?(LOCALE_RE)
            errs[path] << "has an invalid locale: #{key[0, 12]}"
            next
          end
          unless text.is_a?(String)
            errs["#{path}.#{key}"] << "must be text"
            next
          end
          if text.length > max
            errs["#{path}.#{key}"] << "is too long (maximum #{max} characters)"
            next
          end
          out[key] = text
        end
        out["default"] = "" if require_default && !out.key?("default")
        errs[path] << "has too many locales (maximum #{MAX_LOCALES})" if out.size > MAX_LOCALES + 1
        out
      end

      def iso_time_or_nil(value, path, errs, fallback)
        return nil if value.nil? || value == ""

        Time.iso8601(value.to_s).utc.iso8601
      rescue ArgumentError
        errs[path] << "must be an ISO 8601 time"
        fallback
      end
    end

    # {"scope","product_ids","collection_ids"} used by offers and pixels; forms have no scope.
    module Targeting
      SCOPES = %w[all selected].freeze

      module_function

      def normalize(raw, path, errs, with_scope: true)
        raw = Util.hash(raw)
        out = {}
        if with_scope
          out["scope"] = Util.enum(raw.fetch("scope", "all"), "#{path}.scope", errs, "all", SCOPES)
        end
        out["product_ids"] = Util.id_list(raw.fetch("product_ids", []), "#{path}.product_ids", errs, [])
        out["collection_ids"] = Util.id_list(raw.fetch("collection_ids", []), "#{path}.collection_ids", errs, [])
        if with_scope && out["scope"] == "selected" && out["product_ids"].empty? && out["collection_ids"].empty?
          errs[path] << "select at least one product or collection"
        end
        out
      end
    end

    # cod_form_shop_configs.general (B.1.1). Partial updates: `raw` is laid over `current` over `defaults`.
    module General
      OTP_MODES = %w[before_order order_first risk_based].freeze
      BANDS = %w[low medium high].freeze
      RTO_BLOCK_BANDS = %w[medium high].freeze
      EMBED_POSITIONS = %w[before after].freeze
      DISCOUNT_TYPES = [nil, "percentage", "fixed_amount"].freeze
      LANGUAGE = /\A[a-z]{2,3}(-[a-z0-9]{2,8})?\z/.freeze

      # Built-in copy of B.1.1, used when CodForm::Engine::Defaults.general is not available.
      FALLBACK_DEFAULTS = {
        "countries" => [],
        "pages" => { "product" => true, "cart" => true, "drawer" => true, "quick_buy" => false },
        "products" => { "scope" => "all", "include_product_ids" => [], "include_collection_ids" => [],
                        "exclude_product_ids" => [], "exclude_collection_ids" => [] },
        "order_total" => { "min_cents" => nil, "max_cents" => nil, "message" => "" },
        "hide_out_of_stock" => true,
        "cod_only_through_form" => false,
        "cod_fee_taxable" => false,
        "otp" => { "mode" => "before_order", "risk_band" => "medium", "whatsapp" => false, "max_attempts" => 3, "resend_wait_seconds" => 30 },
        "rto" => { "gating_enabled" => false, "block_band" => "high", "min_score" => nil, "message" => "" },
        "discounts" => { "code_field_enabled" => false, "codes_combine_with_offers" => false },
        "prepaid" => { "show_pay_online" => true, "discount_label_enabled" => false, "discount_label" => "" },
        "consent" => { "respect_customer_privacy" => true },
        "branding" => { "hide_powered_by" => false },
        "autocomplete" => { "enabled" => false, "provider" => "google", "google_api_key" => "", "ola_api_key" => "" },
        "abandonment" => { "enabled" => true, "delay_minutes" => 15, "create_draft_order" => false,
                           "recovery_discount" => { "type" => nil, "value" => 0 } },
        "embedded" => { "enabled" => false, "selector" => "", "position" => "after", "form_id" => nil },
        "upsell_window_minutes" => 5,
        "language" => ""
      }.freeze

      # [path in general, value that needs the gate, feature key] — checked only when the request
      # turns the value on (a downgrade keeps the saved configuration, PM Q9).
      GATED = [
        [%w[otp mode], "risk_based", "risk_based_otp"],
        [%w[rto gating_enabled], true, "rto_gating"],
        [%w[branding hide_powered_by], true, "branding_removal"],
        [%w[autocomplete enabled], true, "address_autocomplete"],
        [%w[embedded enabled], true, "embedded_mode"],
        [%w[discounts code_field_enabled], true, "discount_code_field"]
      ].freeze

      module_function

      def defaults(engine_defaults = nil)
        Util.deep_merge(FALLBACK_DEFAULTS, Util.hash(engine_defaults))
      end

      # The stored value completed with defaults (what GET returns).
      def complete(current, engine_defaults = nil)
        normalize({}, current: current, engine_defaults: engine_defaults)["value"]
      end

      def normalize(raw, current: {}, engine_defaults: nil)
        errs = Util.errors
        base = defaults(engine_defaults)
        stored = Util.hash(current)
        raw = Util.hash(raw)
        get = lambda do |*path|
          [raw, stored, base].each do |source|
            node = source
            found = path.all? do |key|
              next false unless node.is_a?(Hash) && node.key?(key)

              node = node[key]
              true
            end
            return node if found
          end
          nil
        end
        dflt = ->(*path) { base.dig(*path) }
        p = ->(*path) { "general.#{path.join('.')}" }

        out = {}
        out["countries"] = Util.countries(get.call("countries"), p.call("countries"), errs, dflt.call("countries"))
        out["pages"] = %w[product cart drawer quick_buy].each_with_object({}) do |page, pages|
          pages[page] = Util.bool(get.call("pages", page), p.call("pages", page), errs, dflt.call("pages", page))
        end
        out["products"] = { "scope" => Util.enum(get.call("products", "scope"), p.call("products", "scope"), errs, "all", Targeting::SCOPES) }
        %w[include_product_ids include_collection_ids exclude_product_ids exclude_collection_ids].each do |key|
          out["products"][key] = Util.id_list(get.call("products", key), p.call("products", key), errs, [])
        end
        if out["products"]["scope"] == "selected" && out["products"]["include_product_ids"].empty? &&
           out["products"]["include_collection_ids"].empty?
          errs[p.call("products")] << "select at least one product or collection"
        end

        min = Util.int_or_nil(get.call("order_total", "min_cents"), p.call("order_total", "min_cents"), errs, nil, min: 0)
        max = Util.int_or_nil(get.call("order_total", "max_cents"), p.call("order_total", "max_cents"), errs, nil, min: 0)
        errs[p.call("order_total", "max_cents")] << "must not be less than the minimum" if min && max && max < min
        out["order_total"] = { "min_cents" => min, "max_cents" => max,
                               "message" => Util.string(get.call("order_total", "message"), p.call("order_total", "message"), errs, "") }

        %w[hide_out_of_stock cod_only_through_form cod_fee_taxable].each do |key|
          out[key] = Util.bool(get.call(key), p.call(key), errs, dflt.call(key))
        end

        out["otp"] = {
          "mode" => Util.enum(get.call("otp", "mode"), p.call("otp", "mode"), errs, "before_order", OTP_MODES),
          "risk_band" => Util.enum(get.call("otp", "risk_band"), p.call("otp", "risk_band"), errs, "medium", BANDS),
          # The form's own channel, sends and wait: nothing is read from the pre-order OTP screen.
          "whatsapp" => Util.bool(get.call("otp", "whatsapp"), p.call("otp", "whatsapp"), errs, false),
          "max_attempts" => Util.int(get.call("otp", "max_attempts"), p.call("otp", "max_attempts"), errs, 3, min: 1, max: 5),
          "resend_wait_seconds" => Util.int(get.call("otp", "resend_wait_seconds"), p.call("otp", "resend_wait_seconds"), errs, 30, min: 15, max: 300)
        }
        # OTP in the form, chosen on the Fraud screen. Not set = off.
        otp_choice = get.call("otp", "enabled")
        out["otp"]["enabled"] = Util.bool(otp_choice, p.call("otp", "enabled"), errs, nil) unless otp_choice.nil?
        out["rto"] = {
          "gating_enabled" => Util.bool(get.call("rto", "gating_enabled"), p.call("rto", "gating_enabled"), errs, false),
          "block_band" => Util.enum(get.call("rto", "block_band"), p.call("rto", "block_band"), errs, "high", RTO_BLOCK_BANDS),
          "min_score" => Util.int_or_nil(get.call("rto", "min_score"), p.call("rto", "min_score"), errs, nil, min: 0, max: 100),
          "message" => Util.string(get.call("rto", "message"), p.call("rto", "message"), errs, "")
        }
        out["discounts"] = bools(get, p, errs, dflt, "discounts", %w[code_field_enabled codes_combine_with_offers])
        out["prepaid"] = bools(get, p, errs, dflt, "prepaid", %w[show_pay_online discount_label_enabled])
        out["prepaid"]["discount_label"] = Util.string(get.call("prepaid", "discount_label"), p.call("prepaid", "discount_label"), errs, "", max: 30)
        out["consent"] = bools(get, p, errs, dflt, "consent", %w[respect_customer_privacy])
        out["branding"] = bools(get, p, errs, dflt, "branding", %w[hide_powered_by])
        out["autocomplete"] = bools(get, p, errs, dflt, "autocomplete", %w[enabled])
        out["autocomplete"]["provider"] = Util.enum(get.call("autocomplete", "provider"), p.call("autocomplete", "provider"), errs, "google", %w[google ola])
        %w[google ola].each do |provider|
          key = "#{provider}_api_key"
          out["autocomplete"][key] = Util.string(get.call("autocomplete", key), p.call("autocomplete", key), errs, "", max: 200)
        end
        chosen = "#{out['autocomplete']['provider']}_api_key"
        if out["autocomplete"]["enabled"] && out["autocomplete"][chosen].empty?
          errs[p.call("autocomplete", chosen)] << "is required when address autocomplete is on"
        end

        out["abandonment"] = bools(get, p, errs, dflt, "abandonment", %w[enabled create_draft_order])
        out["abandonment"]["delay_minutes"] =
          Util.int(get.call("abandonment", "delay_minutes"), p.call("abandonment", "delay_minutes"), errs, 15, min: 5, max: 1_440)
        type = Util.enum(get.call("abandonment", "recovery_discount", "type"),
                         p.call("abandonment", "recovery_discount", "type"), errs, nil, DISCOUNT_TYPES)
        value = Util.number(get.call("abandonment", "recovery_discount", "value") || 0,
                            p.call("abandonment", "recovery_discount", "value"), errs, 0, min: 0)
        if type == "percentage" && value > 100
          errs[p.call("abandonment", "recovery_discount", "value")] << "must be between 0 and 100"
        end
        if type == "fixed_amount" && Util.to_int(value).nil?
          errs[p.call("abandonment", "recovery_discount", "value")] << "must be whole cents"
        end
        out["abandonment"]["recovery_discount"] = { "type" => type, "value" => type.nil? ? 0 : value }

        out["embedded"] = bools(get, p, errs, dflt, "embedded", %w[enabled])
        out["embedded"]["selector"] = Util.selector(get.call("embedded", "selector"), p.call("embedded", "selector"), errs, "")
        out["embedded"]["position"] =
          Util.enum(get.call("embedded", "position"), p.call("embedded", "position"), errs, "after", EMBED_POSITIONS)
        out["embedded"]["form_id"] = Util.int_or_nil(get.call("embedded", "form_id"), p.call("embedded", "form_id"), errs, nil, min: 1)
        if out["embedded"]["enabled"] && out["embedded"]["selector"].empty?
          errs[p.call("embedded", "selector")] << "is required when embedded mode is on"
        end

        out["upsell_window_minutes"] =
          Util.int(get.call("upsell_window_minutes"), p.call("upsell_window_minutes"), errs, 5, min: 1, max: 60)

        # Setup → Form language: "" = the storefront's language, else the locale every buyer sees.
        language = get.call("language").to_s.strip.tr("_", "-").downcase
        if language.empty? || language.match?(LANGUAGE)
          out["language"] = language
        else
          errs[p.call("language")] << "is not a valid language"
          out["language"] = ""
        end

        Util.result(out, errs)
      end

      def bools(get, path, errs, dflt, group, keys)
        keys.each_with_object({}) do |key, out|
          out[key] = Util.bool(get.call(group, key), path.call(group, key), errs, dflt.call(group, key))
        end
      end

      # Feature keys the change old → new turns on (each needs its gate, J.1).
      def gated_features(old_general, new_general)
        GATED.filter_map do |path, gated_value, feature|
          feature if Util.hash(new_general).dig(*path) == gated_value && Util.hash(old_general).dig(*path) != gated_value
        end
      end
    end

    # cod_form_shop_configs.fraud (B.1.2).
    module Fraud
      LIMIT_KINDS = %w[phone email ip].freeze

      FALLBACK_DEFAULTS = {
        "blocked_message" => "",
        "limits" => {
          "phone" => { "enabled" => false, "max_orders" => 3, "window_hours" => 24 },
          "email" => { "enabled" => false, "max_orders" => 3, "window_hours" => 24 },
          "ip" => { "enabled" => false, "max_orders" => 5, "window_hours" => 24 }
        },
        "limit_message" => "",
        "max_quantity_per_order" => nil,
        "max_quantity_message" => "",
        "min_submit_seconds" => 3,
        "honeypot" => true
      }.freeze

      module_function

      def defaults(engine_defaults = nil)
        Util.deep_merge(FALLBACK_DEFAULTS, Util.hash(engine_defaults))
      end

      def complete(current, engine_defaults = nil)
        normalize({}, current: current, engine_defaults: engine_defaults)["value"]
      end

      def normalize(raw, current: {}, engine_defaults: nil)
        errs = Util.errors
        merged = Util.deep_merge(Util.deep_merge(defaults(engine_defaults), Util.hash(current)), Util.hash(raw))
        base = defaults(engine_defaults)

        out = {}
        out["blocked_message"] = Util.string(merged["blocked_message"], "fraud.blocked_message", errs, "")
        limits = Util.hash(merged["limits"])
        out["limits"] = LIMIT_KINDS.each_with_object({}) do |kind, all|
          entry = Util.hash(limits[kind])
          path = "fraud.limits.#{kind}"
          all[kind] = {
            "enabled" => Util.bool(entry["enabled"], "#{path}.enabled", errs, false),
            "max_orders" => Util.int(entry["max_orders"], "#{path}.max_orders", errs, base["limits"][kind]["max_orders"], min: 1, max: 1_000),
            "window_hours" => Util.int(entry["window_hours"], "#{path}.window_hours", errs, 24, min: 1, max: 720)
          }
        end
        out["limit_message"] = Util.string(merged["limit_message"], "fraud.limit_message", errs, "")
        out["max_quantity_per_order"] =
          Util.int_or_nil(merged["max_quantity_per_order"], "fraud.max_quantity_per_order", errs, nil, min: 1, max: 10_000)
        out["max_quantity_message"] = Util.string(merged["max_quantity_message"], "fraud.max_quantity_message", errs, "")
        out["min_submit_seconds"] = Util.int(merged["min_submit_seconds"], "fraud.min_submit_seconds", errs, 3, min: 0, max: 60)
        out["honeypot"] = Util.bool(merged["honeypot"], "fraud.honeypot", errs, true)
        Util.result(out, errs)
      end

      # True when the change turns on a velocity limit (gate `velocity_limits`).
      def enables_limit?(old_fraud, new_fraud)
        LIMIT_KINDS.any? do |kind|
          Util.hash(new_fraud).dig("limits", kind, "enabled") == true &&
            Util.hash(old_fraud).dig("limits", kind, "enabled") != true
        end
      end
    end

    # cod_shipping_rates (C.3).
    module ShippingRate
      PRODUCT_MODES = %w[any only exclude].freeze
      PROVINCE_RE = /\A[A-Z]{2}-[A-Z0-9]{1,10}\z/.freeze
      CURRENCY_RE = /\A[A-Z]{3}\z/.freeze

      module_function

      def empty_conditions
        { "countries" => [], "provinces" => [],
          "subtotal_min_cents" => nil, "subtotal_max_cents" => nil,
          "weight_min_grams" => nil, "weight_max_grams" => nil,
          "quantity_min" => nil, "quantity_max" => nil,
          "products" => { "mode" => "any", "product_ids" => [], "collection_ids" => [] } }
      end

      # `current` = the stored C.3 hash on update (partial updates allowed), {} on create.
      def normalize(raw, current: {})
        errs = Util.errors
        merged = Util.hash(current).merge(Util.hash(raw).reject { |key, _| %w[id source].include?(key) })
        out = {}
        out["name"] = Util.string(merged["name"], "name", errs, "", max: 100, required: true)
        description = Util.string(merged["description"], "description", errs, "", max: 200)
        out["description"] = description.to_s.empty? ? nil : description
        out["price_cents"] = Util.int(merged.fetch("price_cents", 0), "price_cents", errs, 0, min: 0, max: 99_999_999_999)
        currency = merged["currency"].to_s.strip.upcase
        errs["currency"] << "must be a 3-letter ISO 4217 code" unless currency.empty? || currency.match?(CURRENCY_RE)
        out["currency"] = currency.empty? ? nil : currency
        out["position"] = Util.int(merged.fetch("position", 0), "position", errs, 0, min: 0, max: 100_000)
        out["active"] = Util.bool(merged.fetch("active", true), "active", errs, true)
        out["conditions"] = conditions(merged["conditions"], errs)
        Util.result(out, errs)
      end

      def conditions(raw, errs)
        raw = Util.hash(raw)
        out = empty_conditions
        out["countries"] = Util.countries(raw.fetch("countries", []) || [], "conditions.countries", errs, [])
        provinces = raw.fetch("provinces", []) || []
        if provinces.is_a?(Array) && provinces.all? { |code| code.to_s.strip.upcase.match?(PROVINCE_RE) }
          out["provinces"] = provinces.map { |code| code.to_s.strip.upcase }.uniq
        else
          errs["conditions.provinces"] << "must be a list of \"<country>-<province code>\" values, e.g. HU-BU"
        end
        [%w[subtotal_min_cents subtotal_max_cents], %w[weight_min_grams weight_max_grams], %w[quantity_min quantity_max]].each do |low, high|
          min = Util.int_or_nil(raw[low], "conditions.#{low}", errs, nil, min: 0)
          max = Util.int_or_nil(raw[high], "conditions.#{high}", errs, nil, min: 0)
          errs["conditions.#{high}"] << "must not be less than the minimum" if min && max && max < min
          out[low] = min
          out[high] = max
        end
        products = Util.hash(raw["products"])
        mode = Util.enum(products.fetch("mode", "any"), "conditions.products.mode", errs, "any", PRODUCT_MODES)
        out["products"] = {
          "mode" => mode,
          "product_ids" => Util.id_list(products.fetch("product_ids", []), "conditions.products.product_ids", errs, []),
          "collection_ids" => Util.id_list(products.fetch("collection_ids", []), "conditions.products.collection_ids", errs, [])
        }
        if mode != "any" && out["products"]["product_ids"].empty? && out["products"]["collection_ids"].empty?
          errs["conditions.products"] << "select at least one product or collection"
        end
        out
      end
    end

    # cod_offers (C.4).
    module Offer
      TYPES = %w[quantity bump upsell downsell threshold pre_upsell bundle].freeze
      STATUSES = %w[draft active paused archived].freeze
      # Pre-purchase upsells share the order-bump plan gate.
      GATES = { "quantity" => "quantity_offers", "bump" => "order_bumps", "upsell" => "upsell",
                "downsell" => "downsell", "threshold" => "threshold_offers", "pre_upsell" => "order_bumps",
                "bundle" => "quantity_offers" }.freeze
      # Active offers per shop (PM "Limits"); nil = no limit.
      ACTIVE_LIMITS = { "quantity" => 50, "bump" => 20, "downsell" => 1 }.freeze
      MAX_TIERS = 5
      TIER_DISCOUNT_TYPES = %w[none percentage fixed_amount unit_price].freeze
      LAYOUTS = %w[cards list compact].freeze
      BUMP_KINDS = %w[variant custom].freeze
      BUMP_POSITIONS = %w[after_summary before_shipping before_totals].freeze
      ORDER_DISCOUNT_TYPES = %w[percentage fixed_amount].freeze
      THRESHOLD_KINDS = %w[free_shipping free_gift].freeze
      PRE_UPSELL_SOURCES = %w[products collection].freeze
      PRE_UPSELL_MATCH = %w[any all].freeze
      PRE_UPSELL_DISCOUNTS = %w[none percentage fixed_amount fixed_price].freeze
      # "popup": after Complete order; "inline": a card in the form, at a bump position.
      PRE_UPSELL_DISPLAYS = %w[popup inline].freeze
      BUNDLE_PAGE_POSITIONS = %w[above_button below_button before_element after_element].freeze
      MAX_PRE_UPSELL_PRODUCTS = 20
      MAX_CENTS = 99_999_999_999

      module_function

      # `current` = stored wrapper hash on update, {} on create. `offer_type` cannot change on update.
      def normalize(raw, current: {})
        errs = Util.errors
        current = Util.hash(current)
        raw = Util.hash(raw)
        merged = current.merge(raw.reject { |key, _| %w[id ab_test_id].include?(key) })
        out = {}
        out["offer_type"] = Util.enum(merged["offer_type"], "offer_type", errs, nil, TYPES)
        if current["offer_type"] && out["offer_type"] != current["offer_type"]
          errs["offer_type"] << "cannot be changed"
          out["offer_type"] = current["offer_type"]
        end
        out["name"] = Util.string(merged["name"], "name", errs, "", max: 120, required: true)
        out["status"] = Util.enum(merged.fetch("status", "draft"), "status", errs, "draft", STATUSES)
        out["priority"] = Util.int(merged.fetch("priority", 0), "priority", errs, 0, min: 0, max: 100_000)
        out["targeting"] = Targeting.normalize(merged["targeting"], "targeting", errs)
        out["starts_at"] = Util.iso_time_or_nil(merged["starts_at"], "starts_at", errs, nil)
        out["ends_at"] = Util.iso_time_or_nil(merged["ends_at"], "ends_at", errs, nil)
        if out["starts_at"] && out["ends_at"] && out["ends_at"] <= out["starts_at"]
          errs["ends_at"] << "must be after starts_at"
        end
        out["config"] = out["offer_type"] ? config(out["offer_type"], merged["config"], errs) : {}
        Util.result(out, errs)
      end

      def config(type, raw, errs)
        raw = Util.hash(raw)
        case type
        when "quantity" then quantity(raw, errs)
        when "bump" then bump(raw, errs)
        when "downsell" then downsell(raw, errs)
        when "upsell" then upsell(raw, errs)
        when "threshold" then threshold(raw, errs)
        when "pre_upsell" then pre_upsell(raw, errs)
        when "bundle" then bundle(raw, errs)
        else {}
        end
      end

      def quantity(raw, errs)
        out = {
          "title" => Util.localized(raw.fetch("title", {}), "config.title", errs, { "default" => "" }),
          "layout" => Util.enum(raw.fetch("layout", "cards"), "config.layout", errs, "cards", LAYOUTS),
          "show_widget_on_product_page" => Util.bool(raw.fetch("show_widget_on_product_page", true), "config.show_widget_on_product_page", errs, true),
          "tiers" => [],
          "apply_to_higher_quantities" => Util.bool(raw.fetch("apply_to_higher_quantities", true), "config.apply_to_higher_quantities", errs, true)
        }
        tiers = raw["tiers"]
        unless tiers.is_a?(Array) && tiers.size.between?(1, MAX_TIERS) && tiers.all? { |tier| tier.is_a?(Hash) }
          errs["config.tiers"] << "must have 1 to #{MAX_TIERS} tiers"
          return out
        end
        out["tiers"] = tiers.each_with_index.map { |tier, index| quantity_tier(tier, "config.tiers[#{index}]", errs) }
        quantities = out["tiers"].map { |tier| tier["quantity"] }
        errs["config.tiers"] << "each tier needs a different quantity" if quantities.uniq.size != quantities.size
        errs["config.tiers"] << "at most one tier can be preselected" if out["tiers"].count { |tier| tier["preselected"] } > 1
        out["tiers"] = out["tiers"].sort_by { |tier| tier["quantity"] }
        out
      end

      def quantity_tier(tier, path, errs)
        type = Util.enum(tier.fetch("discount_type", "none"), "#{path}.discount_type", errs, "none", TIER_DISCOUNT_TYPES)
        {
          "quantity" => Util.int(tier["quantity"], "#{path}.quantity", errs, 1, min: 1, max: 999),
          "discount_type" => type,
          "value" => discount_value(type, tier.fetch("value", 0), "#{path}.value", errs),
          "label" => Util.localized(tier.fetch("label", {}), "#{path}.label", errs, { "default" => "" }, max: 80),
          "badge" => Util.localized(tier.fetch("badge", {}), "#{path}.badge", errs, { "default" => "" }, max: 40),
          "image_url" => Util.url(tier["image_url"], "#{path}.image_url", errs, ""),
          "preselected" => Util.bool(tier.fetch("preselected", false), "#{path}.preselected", errs, false)
        }
      end

      # percentage → number 0..100; every other type → whole cents; "none" → 0.
      def discount_value(type, value, path, errs)
        case type
        when "none" then 0
        when "percentage" then Util.number(value, path, errs, 0, min: 0, max: 100)
        else Util.int(value, path, errs, 0, min: 0, max: MAX_CENTS)
        end
      end

      def bump(raw, errs)
        kind = Util.enum(raw.fetch("kind", "custom"), "config.kind", errs, "custom", BUMP_KINDS)
        out = {
          "title" => Util.localized(raw.fetch("title", {}), "config.title", errs, { "default" => "" }, max: 120),
          "description" => Util.localized(raw.fetch("description", {}), "config.description", errs, { "default" => "" }),
          "image_url" => Util.url(raw["image_url"], "config.image_url", errs, ""),
          "kind" => kind,
          "variant_id" => Util.id_or_nil(raw["variant_id"], "config.variant_id", errs, nil),
          "price_cents" => Util.int_or_nil(raw["price_cents"], "config.price_cents", errs, nil, min: 0, max: MAX_CENTS),
          "compare_at_cents" => Util.int_or_nil(raw["compare_at_cents"], "config.compare_at_cents", errs, nil, min: 0, max: MAX_CENTS),
          "checked_by_default" => Util.bool(raw.fetch("checked_by_default", false), "config.checked_by_default", errs, false),
          "quantity_picker" => Util.bool(raw.fetch("quantity_picker", false), "config.quantity_picker", errs, false),
          "max_quantity" => Util.int(raw.fetch("max_quantity", 1), "config.max_quantity", errs, 1, min: 1, max: 99),
          "requires_shipping" => Util.bool(raw.fetch("requires_shipping", false), "config.requires_shipping", errs, false),
          "taxable" => Util.bool(raw.fetch("taxable", true), "config.taxable", errs, true),
          "position" => Util.enum(raw.fetch("position", "before_totals"), "config.position", errs, "before_totals", BUMP_POSITIONS)
        }
        errs["config.title.default"] << "is required" if out["title"]["default"].to_s.strip.empty?
        if kind == "variant"
          errs["config.variant_id"] << "is required for a product bump" if out["variant_id"].nil?
        else
          out["variant_id"] = nil
          errs["config.price_cents"] << "is required for a custom bump" if out["price_cents"].nil?
        end
        out
      end

      def downsell(raw, errs)
        type = Util.enum(raw.fetch("discount_type", "percentage"), "config.discount_type", errs, "percentage", ORDER_DISCOUNT_TYPES)
        {
          "trigger_after_closes" => Util.int(raw.fetch("trigger_after_closes", 1), "config.trigger_after_closes", errs, 1, min: 1, max: 10),
          "discount_type" => type,
          "value" => discount_value(type, raw.fetch("value", 10), "config.value", errs),
          "title" => Util.localized(raw.fetch("title", {}), "config.title", errs, { "default" => "" }, max: 120),
          "body" => Util.localized(raw.fetch("body", {}), "config.body", errs, { "default" => "" }),
          "accept_label" => Util.localized(raw.fetch("accept_label", {}), "config.accept_label", errs, { "default" => "" }, max: 60),
          "decline_label" => Util.localized(raw.fetch("decline_label", {}), "config.decline_label", errs, { "default" => "" }, max: 60),
          "timer_seconds" => Util.int(raw.fetch("timer_seconds", 0), "config.timer_seconds", errs, 0, min: 0, max: 3_600)
        }
      end

      def upsell(raw, errs)
        type = Util.enum(raw.fetch("discount_type", "percentage"), "config.discount_type", errs, "percentage", ORDER_DISCOUNT_TYPES + ["none"])
        out = {
          "variant_id" => Util.id_or_nil(raw["variant_id"], "config.variant_id", errs, nil),
          "quantity" => Util.int(raw.fetch("quantity", 1), "config.quantity", errs, 1, min: 1, max: 99),
          "discount_type" => type,
          "value" => discount_value(type, raw.fetch("value", 0), "config.value", errs),
          "title" => Util.localized(raw.fetch("title", {}), "config.title", errs, { "default" => "" }, max: 120),
          "body" => Util.localized(raw.fetch("body", {}), "config.body", errs, { "default" => "" }),
          "accept_label" => Util.localized(raw.fetch("accept_label", {}), "config.accept_label", errs, { "default" => "" }, max: 60),
          "decline_label" => Util.localized(raw.fetch("decline_label", {}), "config.decline_label", errs, { "default" => "" }, max: 60),
          "timer_seconds" => Util.int(raw.fetch("timer_seconds", 120), "config.timer_seconds", errs, 120, min: 0, max: 3_600)
        }
        errs["config.variant_id"] << "is required" if out["variant_id"].nil?
        out
      end

      # Pre-purchase upsell rule. "If the cart has" is the offer's targeting (plus "match" and the
      # cart value range here); "Then offer" is the chosen products or one collection.
      # "candidates" is kept up to date by CodForm::PreUpsellCatalog, never edited by hand.
      def pre_upsell(raw, errs)
        source = Util.enum(raw.fetch("source", "products"), "config.source", errs, "products", PRE_UPSELL_SOURCES)
        type = Util.enum(raw.fetch("discount_type", "percentage"), "config.discount_type", errs, "percentage", PRE_UPSELL_DISCOUNTS)
        value =
          case type
          when "none" then 0
          when "percentage" then Util.number(raw.fetch("value", 10), "config.value", errs, 0, min: 0, max: 100)
          else Util.int(raw.fetch("value", 0), "config.value", errs, 0, min: 0, max: MAX_CENTS)
          end
        out = {
          "display" => Util.enum(raw.fetch("display", "popup"), "config.display", errs, "popup", PRE_UPSELL_DISPLAYS),
          "position" => Util.enum(raw.fetch("position", "before_totals"), "config.position", errs, "before_totals", BUMP_POSITIONS),
          "match" => Util.enum(raw.fetch("match", "any"), "config.match", errs, "any", PRE_UPSELL_MATCH),
          "min_cart_cents" => Util.int_or_nil(raw["min_cart_cents"], "config.min_cart_cents", errs, nil, min: 0, max: MAX_CENTS),
          "max_cart_cents" => Util.int_or_nil(raw["max_cart_cents"], "config.max_cart_cents", errs, nil, min: 0, max: MAX_CENTS),
          "source" => source,
          "product_ids" => Util.id_list(raw.fetch("product_ids", []), "config.product_ids", errs, [], max: MAX_PRE_UPSELL_PRODUCTS),
          "collection_id" => Util.id_or_nil(raw["collection_id"], "config.collection_id", errs, nil),
          "max_products" => Util.int(raw.fetch("max_products", 3), "config.max_products", errs, 3, min: 1, max: 6),
          "discount_type" => type,
          "value" => value,
          "quantity_picker" => Util.bool(raw.fetch("quantity_picker", false), "config.quantity_picker", errs, false),
          "max_quantity" => Util.int(raw.fetch("max_quantity", 3), "config.max_quantity", errs, 3, min: 1, max: 10),
          "title" => Util.localized(raw.fetch("title", {}), "config.title", errs, { "default" => "" }, max: 120),
          "body" => Util.localized(raw.fetch("body", {}), "config.body", errs, { "default" => "" }, require_default: false),
          "accept_label" => Util.localized(raw.fetch("accept_label", {}), "config.accept_label", errs, { "default" => "" }, max: 60, require_default: false),
          "decline_label" => Util.localized(raw.fetch("decline_label", {}), "config.decline_label", errs, { "default" => "" }, max: 60, require_default: false),
          "timer_seconds" => Util.int(raw.fetch("timer_seconds", 0), "config.timer_seconds", errs, 0, min: 0, max: 3_600),
          "candidates" => pre_upsell_candidates(raw["candidates"]),
          "candidates_refreshed_at" => raw["candidates_refreshed_at"].is_a?(String) ? raw["candidates_refreshed_at"][0, 40] : nil
        }
        errs["config.title.default"] << "is required" if out["title"]["default"].to_s.strip.empty?
        if source == "products"
          out["collection_id"] = nil
          errs["config.product_ids"] << "select at least one product to offer" if out["product_ids"].empty?
        else
          out["product_ids"] = []
          errs["config.collection_id"] << "select the collection to offer" if out["collection_id"].nil?
        end
        if out["min_cart_cents"] && out["max_cart_cents"] && out["max_cart_cents"].positive? && out["max_cart_cents"] < out["min_cart_cents"]
          errs["config.max_cart_cents"] << "must be more than the minimum"
        end
        out
      end

      # Bundle: 2 to 6 products sold together with a discount on the whole set, shown on the
      # product pages of its products and / or inside the form. "candidates" as for pre-upsells.
      def bundle(raw, errs)
        type = Util.enum(raw.fetch("discount_type", "percentage"), "config.discount_type", errs, "percentage", PRE_UPSELL_DISCOUNTS)
        value =
          case type
          when "none" then 0
          when "percentage" then Util.number(raw.fetch("value", 10), "config.value", errs, 0, min: 0, max: 100)
          else Util.int(raw.fetch("value", 0), "config.value", errs, 0, min: 0, max: MAX_CENTS)
          end
        out = {
          "product_ids" => Util.id_list(raw.fetch("product_ids", []), "config.product_ids", errs, [], max: 6),
          "discount_type" => type,
          "value" => value,
          "title" => Util.localized(raw.fetch("title", {}), "config.title", errs, { "default" => "" }, max: 120),
          "body" => Util.localized(raw.fetch("body", {}), "config.body", errs, { "default" => "" }, require_default: false),
          "button_label" => Util.localized(raw.fetch("button_label", {}), "config.button_label", errs, { "default" => "" }, max: 60, require_default: false),
          "show_on_product_page" => Util.bool(raw.fetch("show_on_product_page", true), "config.show_on_product_page", errs, true),
          "show_in_form" => Util.bool(raw.fetch("show_in_form", true), "config.show_in_form", errs, true),
          "position" => Util.enum(raw.fetch("position", "after_summary"), "config.position", errs, "after_summary", BUMP_POSITIONS),
          # Product page: above / below the COD button, or before / after a theme element (CSS selector).
          "page_position" => Util.enum(raw.fetch("page_position", "above_button"), "config.page_position", errs, "above_button", BUNDLE_PAGE_POSITIONS),
          "page_selector" => Util.selector(raw.fetch("page_selector", ""), "config.page_selector", errs, ""),
          "candidates" => pre_upsell_candidates(raw["candidates"]),
          "candidates_refreshed_at" => raw["candidates_refreshed_at"].is_a?(String) ? raw["candidates_refreshed_at"][0, 40] : nil
        }
        errs["config.title.default"] << "is required" if out["title"]["default"].to_s.strip.empty?
        errs["config.product_ids"] << "a bundle needs 2 to 6 products" unless out["product_ids"].length.between?(2, 6)
        errs["config.show_in_form"] << "show the bundle on the product page, in the form, or both" unless out["show_on_product_page"] || out["show_in_form"]
        if %w[before_element after_element].include?(out["page_position"]) && out["page_selector"].to_s.strip.empty?
          errs["config.page_selector"] << "enter the CSS selector of the element"
        end
        out
      end

      def pre_upsell_candidates(raw)
        Array(raw).first(25).filter_map do |entry|
          next unless entry.is_a?(Hash)

          product_id = Util.shopify_id(entry["product_id"])
          next if product_id.nil?

          variant_ids = Array(entry["variant_ids"]).filter_map { |id| Util.shopify_id(id) }.uniq.first(10)
          variant_ids.empty? ? nil : { "product_id" => product_id, "variant_ids" => variant_ids }
        end
      end

      def threshold(raw, errs)
        kind = Util.enum(raw.fetch("kind", "free_shipping"), "config.kind", errs, "free_shipping", THRESHOLD_KINDS)
        out = {
          "kind" => kind,
          "threshold_cents" => Util.int(raw["threshold_cents"], "config.threshold_cents", errs, 0, min: 1, max: MAX_CENTS),
          "gift_variant_id" => Util.id_or_nil(raw["gift_variant_id"], "config.gift_variant_id", errs, nil),
          "text_progress" => Util.localized(raw.fetch("text_progress", {}), "config.text_progress", errs, { "default" => "" }),
          "text_reached" => Util.localized(raw.fetch("text_reached", {}), "config.text_reached", errs, { "default" => "" })
        }
        if kind == "free_gift"
          errs["config.gift_variant_id"] << "is required for a free gift" if out["gift_variant_id"].nil?
        else
          out["gift_variant_id"] = nil
        end
        out
      end

      # Message when activating one more offer of this type would pass the limit, else nil.
      def limit_error(offer_type, other_active_count)
        limit = ACTIVE_LIMITS[offer_type]
        return nil if limit.nil? || other_active_count < limit

        "limit reached: at most #{limit} active #{offer_type} offers"
      end

      # OFF-2 on product ids: [{"product_id", "offer_ids"}] for products of `candidate` that are
      # already in another active quantity offer. Same rule as CodForm::Engine::OfferOverlap.
      def product_conflicts(candidate, others)
        mine = Array(Util.hash(candidate["targeting"])["product_ids"]).map(&:to_s)
        return [] if mine.empty?

        mine.filter_map do |product_id|
          ids = others.select { |offer| Array(Util.hash(offer["targeting"])["product_ids"]).map(&:to_s).include?(product_id) }
                      .map { |offer| offer["id"] }
          { "product_id" => product_id, "offer_ids" => ids } if ids.any?
        end
      end

      # Overlap that cannot be decided without Shopify (collections, "all products"): warnings only.
      def overlap_warnings(candidate, others)
        targeting = Util.hash(candidate["targeting"])
        warnings = []
        others.each do |offer|
          other = Util.hash(offer["targeting"])
          shared = Array(targeting["collection_ids"]).map(&:to_s) & Array(other["collection_ids"]).map(&:to_s)
          if shared.any?
            warnings << { "code" => "collection_overlap", "offer_id" => offer["id"], "collection_ids" => shared }
          elsif targeting["scope"] == "all" || other["scope"] == "all"
            warnings << { "code" => "all_products_overlap", "offer_id" => offer["id"] }
          elsif Array(targeting["collection_ids"]).any? || Array(other["collection_ids"]).any?
            warnings << { "code" => "possible_collection_overlap", "offer_id" => offer["id"] }
          end
        end
        warnings
      end
    end

    # cod_offer_ab_tests (B.6).
    module AbTest
      KEY_RE = /\A[a-z0-9_]{1,20}\z/.freeze

      module_function

      def normalize(raw, current: {})
        errs = Util.errors
        merged = Util.hash(current).merge(Util.hash(raw))
        out = {}
        out["name"] = Util.string(merged["name"], "name", errs, "", max: 120, required: true)
        out["offer_type"] = Util.enum(merged["offer_type"], "offer_type", errs, nil, Offer::TYPES)
        variants = merged["variants"]
        unless variants.is_a?(Array) && variants.size.between?(2, 4) && variants.all? { |variant| variant.is_a?(Hash) }
          errs["variants"] << "must have 2 to 4 variants"
          out["variants"] = []
          return Util.result(out, errs)
        end
        out["variants"] = variants.each_with_index.map do |variant, index|
          key = variant["key"].to_s
          errs["variants[#{index}].key"] << "must be 1-20 characters: a-z, 0-9, _" unless key.match?(KEY_RE)
          {
            "key" => key,
            "offer_id" => Util.int_or_nil(variant["offer_id"], "variants[#{index}].offer_id", errs, nil, min: 1),
            "weight" => Util.int(variant["weight"], "variants[#{index}].weight", errs, 0, min: 0, max: 100)
          }
        end
        keys = out["variants"].map { |variant| variant["key"] }
        errs["variants"] << "variant keys must be different" if keys.uniq.size != keys.size
        errs["variants"] << "weights must add up to 100" if out["variants"].sum { |variant| variant["weight"] } != 100
        errs["variants"] << "at least one variant needs an offer" if out["variants"].all? { |variant| variant["offer_id"].nil? }
        Util.result(out, errs)
      end
    end

    # tracking_pixels (C.6).
    module Pixel
      PLATFORMS = %w[meta tiktok ga4 google_ads snapchat pinterest].freeze
      P3_PLATFORMS = %w[snapchat pinterest].freeze
      MAX_PER_PLATFORM = 5
      PURCHASE_EVENTS = %w[purchase lead].freeze
      TIKTOK_EVENTS = %w[complete_payment place_order].freeze
      ID_RE = /\A[A-Za-z0-9_\-]{1,100}\z/.freeze
      EVENT_KEYS = %w[form_open add_payment_info purchase].freeze

      module_function

      # `raw` may carry "access_token" (write-only): returned under "access_token" only when the
      # request sent the key, so an update without it keeps the stored token.
      def normalize(raw, current: {})
        errs = Util.errors
        current = Util.hash(current)
        raw = Util.hash(raw)
        merged = current.merge(raw.reject { |key, _| %w[id access_token access_token_masked].include?(key) })
        out = {}
        out["platform"] = Util.enum(merged["platform"], "platform", errs, nil, PLATFORMS)
        if current["platform"] && out["platform"] != current["platform"]
          errs["platform"] << "cannot be changed"
          out["platform"] = current["platform"]
        end
        pixel_id = merged["pixel_id"].to_s.strip
        errs["pixel_id"] << (pixel_id.empty? ? "is required" : "may contain only letters, digits, - and _") unless pixel_id.match?(ID_RE)
        errs["pixel_id"] << "must start with AW-" if out["platform"] == "google_ads" && !pixel_id.empty? && !pixel_id.start_with?("AW-")
        out["pixel_id"] = pixel_id
        out["enabled"] = Util.bool(merged.fetch("enabled", true), "enabled", errs, true)
        out["position"] = Util.int(merged.fetch("position", 0), "position", errs, 0, min: 0, max: 1_000)
        out["targeting"] = Targeting.normalize(merged["targeting"], "targeting", errs)
        out["config"] = config(out["platform"], merged["config"], errs)
        if raw.key?("access_token")
          token = raw["access_token"]
          if token.nil? || token.is_a?(String)
            out["access_token"] = token.to_s.strip.empty? ? nil : token.strip
            errs["access_token"] << "is too long" if token.to_s.length > 2_000
          else
            errs["access_token"] << "must be text"
          end
        end
        Util.result(out, errs)
      end

      def config(platform, raw, errs)
        raw = Util.hash(raw)
        events = Util.hash(raw["events"])
        out = {
          "browser" => Util.bool(raw.fetch("browser", true), "config.browser", errs, true),
          "server" => Util.bool(raw.fetch("server", true), "config.server", errs, true),
          "purchase_event" => Util.enum(raw.fetch("purchase_event", "purchase"), "config.purchase_event", errs, "purchase", PURCHASE_EVENTS),
          "events" => EVENT_KEYS.each_with_object({}) do |key, all|
            fallback = key != "add_payment_info"
            all[key] = Util.bool(events.fetch(key, fallback), "config.events.#{key}", errs, fallback)
          end,
          "test_event_code" => Util.string(raw["test_event_code"], "config.test_event_code", errs, "", max: 100),
          "conversion_label" => Util.string(raw["conversion_label"], "config.conversion_label", errs, "", max: 100),
          "ad_account_id" => Util.string(raw["ad_account_id"], "config.ad_account_id", errs, "", max: 100)
        }
        if platform == "tiktok" && raw.key?("tiktok_event")
          out["tiktok_event"] = Util.enum(raw["tiktok_event"], "config.tiktok_event", errs, "complete_payment", TIKTOK_EVENTS)
        end
        errs["config.ad_account_id"] << "is required for Pinterest server events" if platform == "pinterest" && out["server"] && out["ad_account_id"].empty?
        out
      end

      # Feature keys a pixel needs (J.1): `first_pixel` or `extra_pixels` by count, `pixels_p3` for
      # Snapchat, Pinterest and product-specific pixels.
      def required_features(pixel, others_on_platform:)
        features = [others_on_platform.zero? ? "first_pixel" : "extra_pixels"]
        features << "pixels_p3" if P3_PLATFORMS.include?(pixel["platform"]) || Util.hash(pixel["targeting"])["scope"] == "selected"
        features
      end

      def mask_token(token)
        text = token.to_s
        return nil if text.empty?

        "••••#{text.length > 8 ? text[-4, 4] : ''}"
      end
    end

    # cod_block_entries (C.5): bulk preparation for POST /cod_form/block_entries.
    module BlockEntries
      KINDS = %w[phone email ip].freeze
      MAX_PER_KIND = 5_000
      MAX_PER_REQUEST = 5_000

      module_function

      # Same normalisation as CodForm::BlockEntry.normalize (B.7).
      def normalize_value(kind, value)
        text = value.to_s.strip
        case kind
        when "phone" then text.gsub(/\D/, "").sub(/\A0+/, "")
        when "email" then text.downcase
        else text
        end
      end

      def valid?(kind, normalized)
        case kind
        when "phone" then normalized.match?(/\A\d{5,15}\z/)
        when "email" then normalized.match?(/\A(\*|[^@\s*]+)@[^@\s*]+\.[^@\s*]+\z/)
        when "ip" then valid_ip?(normalized)
        else false
        end
      end

      def valid_ip?(text)
        return false unless text.match?(%r{\A[0-9a-fA-F:.]+(/\d{1,3})?\z})

        IPAddr.new(text)
        true
      rescue IPAddr::Error, ArgumentError
        false
      end

      # values: raw strings. existing: Array/Set of value_normalized already stored for this kind.
      # => {"entries" => [{"value","value_normalized"}], "skipped" => n, "invalid" => n, "over_limit" => n, "errors" => {...}}
      def prepare(kind:, values:, existing:)
        errs = Util.errors
        errs["kind"] << "must be one of: #{KINDS.join(', ')}" unless KINDS.include?(kind)
        errs["values"] << "must be a list" unless values.is_a?(Array)
        errs["values"] << "is too long (maximum #{MAX_PER_REQUEST} entries per request)" if values.is_a?(Array) && values.size > MAX_PER_REQUEST
        errs["values"] << "is empty" if values.is_a?(Array) && values.empty?
        clean = errs.reject { |_, list| list.empty? }
        return { "entries" => [], "skipped" => 0, "invalid" => 0, "over_limit" => 0, "errors" => clean } unless clean.empty?

        seen = {}
        existing.each { |value| seen[value] = true }
        room = MAX_PER_KIND - seen.size
        entries = []
        invalid = duplicate = over = 0
        values.each do |value|
          normalized = normalize_value(kind, value)
          if !value.is_a?(String) || value.length > 255 || !valid?(kind, normalized)
            invalid += 1
          elsif seen[normalized]
            duplicate += 1
          elsif entries.size >= room
            over += 1
          else
            seen[normalized] = true
            entries << { "value" => value.strip, "value_normalized" => normalized }
          end
        end
        { "entries" => entries, "skipped" => invalid + duplicate + over, "invalid" => invalid,
          "over_limit" => over, "errors" => {} }
      end
    end

    # Structural pre-check of a form draft before CodForm::Engine::FormConfig.normalize (C.2):
    # rejects what must never be stored (unknown block / field types, oversized payloads).
    module FormDraft
      BLOCK_TYPES = %w[order_summary quantity_offer fields shipping bumps discount totals submit
                       rich_text image trust_badges countdown threshold_bar].freeze
      BUILTIN_FIELD_TYPES = %w[text tel email country province city postal textarea consent].freeze
      CUSTOM_FIELD_TYPES = %w[text textarea select radio checkbox date].freeze
      BUILTIN_KEYS = %w[first_name last_name phone email country address1 address2 province city zip
                        gst_number note marketing_consent].freeze
      CUSTOM_KEY_RE = /\Acf_[a-z0-9]{8}\z/.freeze
      MODES = %w[popup embedded].freeze
      MAX_BLOCKS = 40
      MAX_FIELDS = 60
      MAX_BYTES = 200_000

      module_function

      def errors(raw)
        errs = Util.errors
        unless raw.is_a?(Hash)
          errs["draft_config"] << "must be an object"
          return errs
        end
        errs["draft_config"] << "is too large" if JSON.generate(raw).bytesize > MAX_BYTES
        errs["draft_config.mode"] << "must be one of: #{MODES.join(', ')}" if raw.key?("mode") && !MODES.include?(raw["mode"])
        check_blocks(raw["blocks"], errs) if raw.key?("blocks")
        check_fields(raw["fields"], errs) if raw.key?("fields")
        check_texts(raw["texts"], errs) if raw.key?("texts")
        errs.reject { |_, list| list.empty? }
      end

      def check_blocks(blocks, errs)
        unless blocks.is_a?(Array) && blocks.size <= MAX_BLOCKS && blocks.all? { |block| block.is_a?(Hash) }
          errs["draft_config.blocks"] << "must be a list of at most #{MAX_BLOCKS} blocks"
          return
        end
        blocks.each_with_index do |block, index|
          next if BLOCK_TYPES.include?(block["type"])

          errs["draft_config.blocks[#{index}].type"] << "unknown block type"
        end
        ids = blocks.map { |block| block["id"] }
        errs["draft_config.blocks"] << "block ids must be unique" if ids.uniq.size != ids.size
      end

      def check_fields(fields, errs)
        unless fields.is_a?(Array) && fields.size <= MAX_FIELDS && fields.all? { |field| field.is_a?(Hash) }
          errs["draft_config.fields"] << "must be a list of at most #{MAX_FIELDS} fields"
          return
        end
        fields.each_with_index do |field, index|
          key = field["key"].to_s
          custom = key.match?(CUSTOM_KEY_RE)
          unless custom || BUILTIN_KEYS.include?(key)
            errs["draft_config.fields[#{index}].key"] << "unknown field key"
            next
          end
          allowed = custom ? CUSTOM_FIELD_TYPES : BUILTIN_FIELD_TYPES
          errs["draft_config.fields[#{index}].type"] << "unknown field type" unless allowed.include?(field["type"])
        end
        keys = fields.map { |field| field["key"] }
        errs["draft_config.fields"] << "field keys must be unique" if keys.uniq.size != keys.size
      end

      def check_texts(texts, errs)
        unless texts.is_a?(Hash) && texts.values.all? { |set| set.is_a?(Hash) }
          errs["draft_config.texts"] << "must be an object of locale => texts"
          return
        end
        errs["draft_config.texts"] << "has too many locales (maximum #{MAX_LOCALES})" if texts.size > MAX_LOCALES
        texts.each do |locale, set|
          set.each do |text_key, text|
            next if text.is_a?(String) && text.length <= MAX_TEXT

            errs["draft_config.texts.#{locale}.#{text_key}"] << "must be text of at most #{MAX_TEXT} characters"
          end
        end
      end

      # FRM-21: applying a template replaces `design` and the block order only; content blocks the
      # template does not know keep their relative order, and the submit block stays last.
      def apply_template(config, template)
        out = Util.deep_dup(Util.hash(config))
        template = Util.hash(template)
        out["design"] = Util.deep_dup(template["design"]) if template["design"].is_a?(Hash)
        order = Array(template["blocks_order"]).map(&:to_s)
        blocks = Array(out["blocks"]).select { |block| block.is_a?(Hash) }
        sorted = blocks.each_with_index.sort_by { |block, index| [order.index(block["id"].to_s) || order.size, index] }.map(&:first)
        submit, rest = sorted.partition { |block| block["type"] == "submit" }
        out["blocks"] = rest + submit
        out
      end

      # True when a draft uses custom fields (gate `custom_fields`).
      def custom_fields?(config)
        Array(Util.hash(config)["fields"]).any? { |field| field.is_a?(Hash) && field["key"].to_s.start_with?("cf_") }
      end
    end

    # GET list paging (D.14): {"page","pages","count"}.
    module Paging
      module_function

      def page(value)
        number = Util.to_int(value) || 1
        number < 1 ? 1 : [number, 100_000].min
      end

      def meta(page:, per:, count:)
        pages = count.zero? ? 1 : (count.to_f / per).ceil
        { "page" => page, "pages" => pages, "count" => count }
      end
    end
  end
end
