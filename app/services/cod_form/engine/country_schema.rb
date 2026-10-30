# frozen_string_literal: true

require "json"

module CodForm
  module Engine
    # Per-country address schema and phone rules (ARCHITECTURE E.10, FRM-5).
    # Data file: config/cod_form/countries.json.
    class CountrySchema
      DEFAULT_PATH = File.expand_path("../../../../config/cod_form/countries.json", __dir__)
      DEFAULT_KEY = "default"
      FALLBACK = {
        "dial_code" => "",
        "phone" => { "min" => 6, "max" => 14, "strip_leading_zero" => false, "mobile_prefixes" => [], "enforce_mobile" => false },
        "address" => {
          "province" => { "mode" => "auto" }, "city" => { "mode" => "free" },
          "zip" => { "required" => false, "regex" => "", "label_key" => "label_zip" }
        }
      }.freeze

      @cache = {}
      @mutex = Mutex.new

      class << self
        # The only I/O of the engines; the path is injectable.
        def load(path = DEFAULT_PATH)
          key = path.to_s
          @mutex.synchronize do
            @cache[key] ||= JSON.parse(File.read(key, encoding: "UTF-8"))
          end
        end

        def reset_cache!
          @mutex.synchronize { @cache = {} }
        end

        # => merged schema hash for one country (the "default" entry filled in), plus "country".
        def for(country:, data: nil)
          data = load if data.nil?
          code = country.to_s.strip.upcase
          default = deep_merge(FALLBACK, data[DEFAULT_KEY].is_a?(Hash) ? data[DEFAULT_KEY] : {})
          entry = data[code].is_a?(Hash) && code != DEFAULT_KEY.upcase ? data[code] : {}
          deep_merge(default, entry).merge("country" => code, "known" => !entry.empty?)
        end

        # The province field of a country is either a select fed by a province list or absent.
        # "auto" (and a "select" whose list is missing) cannot be decided from the schema file
        # alone, so the caller says whether a province list exists and gets back a schema whose
        # `address.province.mode` is always "select" or "hidden". Server validation, the session
        # response and the geo endpoint all use the resolved schema, so the browser and
        # FormValidator agree on whether the field exists (a hidden field is never required).
        # `address.province.declared_mode` keeps the mode of the data file.
        def resolve(schema, has_provinces:)
          schema = schema.is_a?(Hash) ? schema : {}
          address = schema["address"].is_a?(Hash) ? schema["address"] : {}
          province = address["province"].is_a?(Hash) ? address["province"] : {}
          declared = (province["declared_mode"] || province["mode"]).to_s
          declared = "auto" if declared.empty?
          mode = declared != "hidden" && has_provinces ? "select" : "hidden"
          schema.merge("address" => address.merge("province" => province.merge("mode" => mode, "declared_mode" => declared)))
        end

        # => the "rules" argument of Phone.validate
        def phone_rules(country:, data: nil)
          schema = self.for(country: country, data: data)
          schema["phone"].merge("dial_code" => schema["dial_code"])
        end

        def countries(data: nil)
          data = load if data.nil?
          data.keys.reject { |key| key == DEFAULT_KEY }.sort
        end

        private

        def deep_merge(base, override)
          result = {}
          base.each { |key, value| result[key] = copy(value) }
          override.each do |key, value|
            result[key] = result[key].is_a?(Hash) && value.is_a?(Hash) ? deep_merge(result[key], value) : copy(value)
          end
          result
        end

        def copy(value)
          case value
          when Hash then value.each_with_object({}) { |(key, item), out| out[key] = copy(item) }
          when Array then value.map { |item| copy(item) }
          else value
          end
        end
      end
    end
  end
end
