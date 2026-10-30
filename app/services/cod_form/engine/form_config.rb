# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "defaults"
end

module CodForm
  module Engine
    # Form config normaliser (ARCHITECTURE C.2 / E.13). Unknown keys are dropped, missing keys filled.
    class FormConfig
      SCHEMA = 1
      MODES = %w[popup embedded].freeze
      CORE_BLOCK_TYPES = %w[order_summary quantity_offer fields shipping bumps discount totals submit].freeze
      CONTENT_BLOCK_TYPES = %w[rich_text image trust_badges countdown threshold_bar].freeze
      BUILT_IN_TYPES = %w[text tel email country province city postal textarea consent].freeze
      CUSTOM_TYPES = %w[text textarea select radio checkbox date].freeze
      CUSTOM_KEY = /\Acf_[a-z0-9]{8}\z/.freeze
      COLOR = /\A#[0-9a-fA-F]{6}\z/.freeze
      COLOR_KEYS = %w[primary on_primary text muted background surface border error].freeze
      THANK_YOU_TYPES = %w[order_status custom_url message whatsapp].freeze
      ALLOWED_TAGS = %w[b i u a br p ul ol li strong em span].freeze
      FOLLOW_SCHEMA_KEYS = %w[zip province city].freeze
      ALWAYS_ENABLED = %w[phone country].freeze
      MAX_TEXT = 300
      MAX_LOCALES = 12
      MAX_REGEX = 200
      LOCALE = /\A[a-z]{2,3}([-_][A-Za-z0-9]{2,8})*\z/.freeze

      class << self
        # => {"config"=>…, "errors"=>[{"path","code"}], "warnings"=>[{"path","code"}]}
        def normalize(raw)
          raw = raw.is_a?(Hash) ? raw : {}
          defaults = Defaults.form_config
          errors = []
          warnings = []

          mode = raw["mode"].to_s
          if mode.empty? then mode = defaults["mode"]
          elsif !MODES.include?(mode)
            errors << issue("mode", "invalid_value")
            mode = defaults["mode"]
          end

          config = {
            "schema" => SCHEMA,
            "mode" => mode,
            "design" => design(raw["design"], defaults["design"], errors),
            "blocks" => blocks(raw["blocks"], defaults["blocks"], errors, warnings),
            "fields" => fields(raw["fields"], defaults["fields"], errors, warnings),
            "texts" => texts(raw.key?("texts") ? raw["texts"] : defaults["texts"], errors),
            "thank_you" => thank_you(raw["thank_you"], defaults["thank_you"], errors),
            "steps" => { "phone_first" => hash(raw["steps"])["phone_first"] == true },
            "pay_online" => { "enabled" => hash(raw["pay_online"])["enabled"] != false },
            "language" => language(raw["language"])
          }
          { "config" => config, "errors" => errors, "warnings" => warnings }
        end

        # The form's own language ("hi", "fr"…): buyers see the form in it whatever the storefront
        # language is. "" = follow the storefront language (the default).
        def language(raw)
          code = raw.to_s.strip.tr("_", "-").downcase
          code.match?(LOCALE) && code.length <= 12 ? code : ""
        end

        # The locale the storefront form uses: the form's own language when one is set (Designer →
        # Texts), else the shop's form language (Setup → Form language), else the buyer's storefront
        # locale.
        def storefront_locale(config, requested, shop_language = nil)
          own = config.is_a?(Hash) ? language(config["language"]) : ""
          own = language(shop_language) if own.empty?
          own.empty? ? requested : own
        end

        # Texts reduced to the active locale (and its language part) plus "en".
        def for_storefront(config, locale:)
          config = config.is_a?(Hash) ? config : {}
          all = hash(config["texts"])
          keep = [locale.to_s, locale.to_s.split(/[-_]/).first.to_s, "en"].reject(&:empty?).uniq
          config.merge("texts" => all.select { |key, _| keep.include?(key) })
        end

        # Keeps only b i u a br p ul ol li strong em span; attributes dropped except https href on <a>.
        def sanitize_html(html)
          text = html.to_s.gsub(%r{<(script|style)\b[^>]*>.*?</\1\s*>}mi, "").gsub(/<!--.*?-->/m, "")
          text = text.gsub(%r{<\s*(/?)\s*([A-Za-z][A-Za-z0-9]*)\b([^<>]*)>}) do
            closing = Regexp.last_match(1)
            tag = Regexp.last_match(2).downcase
            attributes = Regexp.last_match(3)
            next "" unless ALLOWED_TAGS.include?(tag)
            next "</#{tag}>" unless closing.empty?
            next "<br>" if tag == "br"

            if tag == "a"
              href = attributes[/\bhref\s*=\s*"([^"]*)"/i, 1] || attributes[/\bhref\s*=\s*'([^']*)'/i, 1]
              href = href.to_s.strip
              next %(<a href="#{href.gsub('"', '%22')}" target="_blank" rel="noopener noreferrer">) if href.match?(%r{\Ahttps://[^\s<>"']+\z}i)

              next "<a>"
            end
            "<#{tag}>"
          end
          text.gsub("<") { |match| Regexp.last_match.post_match.match?(%r{\A/?(#{ALLOWED_TAGS.join('|')})(>| href=")}) ? match : "&lt;" }
        end

        private

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def issue(path, code)
          { "path" => path, "code" => code }
        end

        def integer(value, default, min, max)
          number = value.is_a?(Numeric) ? value.round : Integer(value.to_s, exception: false)
          number.nil? ? default : [[number, min].max, max].min
        end

        def https_url(value)
          text = value.to_s.strip
          text.match?(%r{\Ahttps://[^\s<>"']+\z}i) && text.length <= 2000 ? text : ""
        end

        THEMES = %w[classic express].freeze

        def design(raw, defaults, errors)
          raw = hash(raw)
          out = {}
          COLOR_KEYS.each do |key|
            value = raw[key]
            if value.nil? then out[key] = defaults[key]
            elsif value.to_s.match?(COLOR) then out[key] = value.to_s.downcase
            else
              errors << issue("design.#{key}", "invalid_color")
              out[key] = defaults[key]
            end
          end
          out["radius"] = integer(raw["radius"], defaults["radius"], 0, 40)
          out["field_radius"] = integer(raw["field_radius"], defaults["field_radius"], 0, 40)
          out["density"] = %w[comfortable compact].include?(raw["density"].to_s) ? raw["density"].to_s : defaults["density"]
          # Look of the whole form. "classic" is the original one; "express" is the look of the
          # COD King checkout widget (styling only, loaded as its own storefront file).
          out["theme"] = THEMES.include?(raw["theme"].to_s) ? raw["theme"].to_s : "classic"
          header = hash(raw["header"])
          logo = header["logo_url"].to_s.strip
          errors << issue("design.header.logo_url", "invalid_url") if !logo.empty? && https_url(logo).empty?
          out["header"] = { "show_title" => header["show_title"] != false, "logo_url" => https_url(logo),
                            "show_close" => header["show_close"] != false }
          out["sticky_submit"] = raw["sticky_submit"] != false
          out["hide_shipping_selector_when_single"] = raw["hide_shipping_selector_when_single"] != false
          out
        end

        def blocks(raw, defaults, errors, warnings)
          list = raw.is_a?(Array) ? raw : []
          out = []
          seen = {}
          singles = {}
          list.each_with_index do |block, index|
            next unless block.is_a?(Hash)

            type = block["type"].to_s
            unless CORE_BLOCK_TYPES.include?(type) || CONTENT_BLOCK_TYPES.include?(type)
              warnings << issue("blocks[#{index}]", "unknown_block_type")
              next
            end
            id = block["id"].to_s.strip
            id = type if id.empty?
            unless id.match?(/\A[A-Za-z0-9_-]{1,40}\z/)
              errors << issue("blocks[#{index}].id", "invalid_id")
              next
            end
            if seen[id] || (single_type?(type) && singles[type])
              errors << issue("blocks[#{index}]", "duplicate_block")
              next
            end
            seen[id] = true
            singles[type] = true
            out << { "id" => id, "type" => type, "enabled" => block["enabled"] != false,
                     "settings" => block_settings(type, hash(block["settings"]), "blocks[#{index}].settings", errors) }
          end

          # every core block of the default form exists exactly once
          defaults.each do |block|
            exists = block["type"] == "fields" ? out.any? { |b| b["type"] == "fields" && b["settings"]["group"] == block["settings"]["group"] } : out.any? { |b| b["type"] == block["type"] }
            next if exists

            copy = { "id" => unique_id(block["id"], seen), "type" => block["type"], "enabled" => block["enabled"],
                     "settings" => block["settings"].dup }
            copy["enabled"] = false if raw.is_a?(Array) && !raw.empty? && !%w[submit fields totals].include?(block["type"])
            seen[copy["id"]] = true
            out << copy
          end

          submit = out.find { |block| block["type"] == "submit" }
          submit["enabled"] = true
          out.delete(submit)
          out << submit
          out
        end

        def single_type?(type)
          %w[order_summary quantity_offer shipping bumps discount totals submit].include?(type)
        end

        def unique_id(id, seen)
          candidate = id
          counter = 2
          while seen[candidate]
            candidate = "#{id}_#{counter}"
            counter += 1
          end
          candidate
        end

        def block_settings(type, settings, path, errors)
          case type
          when "order_summary"
            { "show_image" => settings["show_image"] != false, "show_compare_at" => settings["show_compare_at"] != false,
              "show_quantity" => settings["show_quantity"] != false }
          when "fields"
            group = %w[contact address].include?(settings["group"].to_s) ? settings["group"].to_s : "contact"
            title_key = settings["title_key"].to_s
            { "group" => group, "title_key" => title_key.match?(/\A[a-z0-9_]{1,60}\z/) ? title_key : "#{group}_title" }
          when "totals" then { "show_tax_line" => settings["show_tax_line"] == true }
          when "submit" then { "show_total_in_button" => settings["show_total_in_button"] != false }
          when "rich_text" then { "html" => sanitize_html(settings["html"].to_s[0, 5000]) }
          when "image"
            url = https_url(settings["url"])
            errors << issue("#{path}.url", "invalid_url") if url.empty?
            { "url" => url, "alt" => settings["alt"].to_s[0, MAX_TEXT], "link" => https_url(settings["link"]) }
          when "trust_badges"
            items = Array(settings["items"]).select { |item| item.is_a?(Hash) }.first(8).map do |item|
              { "icon" => item["icon"].to_s[0, 40], "text" => item["text"].to_s[0, MAX_TEXT] }
            end
            { "items" => items }
          when "countdown"
            text_key = settings["text_key"].to_s
            { "minutes" => integer(settings["minutes"], 10, 1, 1440),
              "text_key" => text_key.match?(/\A[a-z0-9_]{1,60}\z/) ? text_key : "" }
          when "threshold_bar" then { "offer_id" => settings["offer_id"].is_a?(Integer) ? settings["offer_id"] : nil }
          else {}
          end
        end

        def fields(raw, defaults, errors, warnings)
          list = raw.is_a?(Array) ? raw : []
          by_key = defaults.each_with_object({}) { |field, map| map[field["key"]] = field }
          out = []
          seen = {}
          list.each_with_index do |field, index|
            next unless field.is_a?(Hash)

            key = field["key"].to_s
            path = "fields[#{index}]"
            built_in = by_key[key]
            unless built_in || key.match?(CUSTOM_KEY)
              errors << issue("#{path}.key", "invalid_key")
              next
            end
            if seen[key]
              errors << issue(path, "duplicate_field")
              next
            end
            seen[key] = true
            out << (built_in ? built_in_field(field, built_in, path, errors, warnings) : custom_field(field, path, errors))
          end
          defaults.each { |field| out << copy(field) unless seen[field["key"]] }
          out.compact
        end

        def built_in_field(field, default, path, errors, warnings)
          key = default["key"]
          out = { "key" => key, "type" => default["type"], "group" => default["group"] }
          enabled = field.key?("enabled") ? field["enabled"] == true : default["enabled"]
          if ALWAYS_ENABLED.include?(key) && !enabled
            warnings << issue("#{path}.enabled", "cannot_disable")
            enabled = true
          end
          out["enabled"] = enabled
          required = field.key?("required") ? field["required"] : default["required"]
          out["required"] =
            if required.nil? then FOLLOW_SCHEMA_KEYS.include?(key) ? nil : default["required"]
            else required == true
            end
          out["required"] = true if ALWAYS_ENABLED.include?(key)
          out["width"] = %w[half full].include?(field["width"].to_s) ? field["width"].to_s : default["width"]
          out["autocomplete"] = default["autocomplete"] if default.key?("autocomplete")
          if default.key?("only_countries")
            countries = field.key?("only_countries") ? field["only_countries"] : default["only_countries"]
            out["only_countries"] = Array(countries).map { |c| c.to_s.upcase }.select { |c| c.match?(/\A[A-Z]{2}\z/) }.uniq
          end
          if default.key?("validation")
            out["validation"] = validation(field.key?("validation") ? field["validation"] : default["validation"], "#{path}.validation", errors)
          end
          if key == "marketing_consent"
            out["default_checked"] = field["default_checked"] == true
            channels = Array(field.key?("channels") ? field["channels"] : default["channels"]).map(&:to_s) & %w[sms email]
            out["channels"] = channels.empty? ? %w[sms email] : channels
          end
          out
        end

        def custom_field(field, path, errors)
          type = field["type"].to_s
          unless CUSTOM_TYPES.include?(type)
            errors << issue("#{path}.type", "invalid_type")
            return nil
          end
          out = {
            "key" => field["key"].to_s, "type" => type,
            "group" => %w[contact address].include?(field["group"].to_s) ? field["group"].to_s : "address",
            "enabled" => field["enabled"] != false, "required" => field["required"] == true,
            "width" => %w[half full].include?(field["width"].to_s) ? field["width"].to_s : "full",
            "validation" => validation(field["validation"], "#{path}.validation", errors)
          }
          if %w[select radio].include?(type)
            options = Array(field["options"]).select { |option| option.is_a?(Hash) && !option["value"].to_s.empty? }.first(50).map do |option|
              { "value" => option["value"].to_s[0, 100], "label" => locale_map(option["label"], nil, nil) }
            end
            errors << issue("#{path}.options", "required") if options.empty?
            out["options"] = options
          end
          out
        end

        def validation(raw, path, errors)
          raw = hash(raw)
          out = {}
          %w[min max].each do |key|
            next if raw[key].nil?

            value = integer(raw[key], nil, 0, 5000)
            value.nil? ? errors << issue("#{path}.#{key}", "invalid_value") : out[key] = value
          end
          if out["min"] && out["max"] && out["min"] > out["max"]
            errors << issue("#{path}.min", "min_greater_than_max")
            out.delete("min")
          end
          regex = raw["regex"].to_s
          unless regex.empty?
            if regex.length > MAX_REGEX
              errors << issue("#{path}.regex", "too_long")
            elsif !compiles?(regex)
              errors << issue("#{path}.regex", "invalid_regex")
            else
              out["regex"] = regex
            end
          end
          out["latin_only"] = true if raw["latin_only"] == true
          out
        end

        def compiles?(source)
          Regexp.new(source)
          true
        rescue RegexpError
          false
        end

        def texts(raw, errors)
          raw = hash(raw)
          out = {}
          raw.each do |locale, strings|
            locale = locale.to_s
            next unless strings.is_a?(Hash)

            unless locale.match?(LOCALE)
              errors << issue("texts.#{locale}", "invalid_locale")
              next
            end
            if out.length >= MAX_LOCALES
              errors << issue("texts", "too_many_locales")
              break
            end
            out[locale] = strings.each_with_object({}) do |(key, value), map|
              key = key.to_s
              next unless key.match?(/\A[a-z0-9_]{1,80}\z/) && (value.is_a?(String) || value.is_a?(Numeric))

              text = value.to_s
              if text.length > MAX_TEXT
                errors << issue("texts.#{locale}.#{key}", "too_long")
                text = text[0, MAX_TEXT]
              end
              map[key] = text
            end
          end
          out
        end

        def locale_map(raw, path, errors)
          map = raw.is_a?(Hash) ? raw : (raw.to_s.empty? ? {} : { "default" => raw.to_s })
          map.each_with_object({}) do |(locale, value), out|
            next unless locale.to_s == "default" || locale.to_s.match?(LOCALE)

            text = value.to_s
            if text.length > MAX_TEXT
              errors << issue("#{path}.#{locale}", "too_long") if errors
              text = text[0, MAX_TEXT]
            end
            out[locale.to_s] = text
          end
        end

        def thank_you(raw, defaults, errors)
          raw = hash(raw)
          type = raw["type"].to_s
          if type.empty? then type = defaults["type"]
          elsif !THANK_YOU_TYPES.include?(type)
            errors << issue("thank_you.type", "invalid_value")
            type = defaults["type"]
          end
          url = raw["url"].to_s.strip
          # {variables} are allowed in the URL; they are checked without the braces
          probe = url.gsub(/\{[a-z_]+\}/, "x")
          valid_url = probe.match?(%r{\Ahttps://[^\s<>"']+\z}i) && url.length <= 2000
          errors << issue("thank_you.url", "invalid_url") if (type == "custom_url" && !valid_url) || (!url.empty? && !valid_url)
          whatsapp = hash(raw["whatsapp"])
          phone = whatsapp["phone"].to_s.gsub(/\D/, "")
          errors << issue("thank_you.whatsapp.phone", "required") if type == "whatsapp" && phone.length < 6
          message = raw.key?("message") ? raw["message"] : defaults["message"]
          whatsapp_message = whatsapp.key?("message") ? whatsapp["message"] : defaults["whatsapp"]["message"]
          {
            "type" => type,
            "url" => valid_url ? url : "",
            "message" => locale_map(message, "thank_you.message", errors),
            "whatsapp" => { "phone" => phone, "message" => locale_map(whatsapp_message, "thank_you.whatsapp.message", errors) }
          }
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
