# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "phone"
end

module CodForm
  module Engine
    # Server-side twin of the client validation (ARCHITECTURE E.13, FRM-3, FRM-7, FRM-15).
    class FormValidator
      SPECIFIC_ERRORS = %w[first_name last_name phone email address1 province city zip gst_number].freeze
      EMAIL = /\A[^@\s]+@[^@\s.]+(\.[^@\s.]+)+\z/.freeze
      REGEX_TIMEOUT = 0.05
      VALUE_GROUPS = %w[contact address fields custom_fields].freeze

      class << self
        # config = form config (C.2); schema = CountrySchema.for(...); values = flat {"field key" => value}
        # (a hash with "contact"/"address"/"fields"/"custom_fields" sub-hashes, as in D.6, is flattened).
        # => {"valid"=>bool, "fields"=>{"zip"=>"error_zip"}}
        def validate(config:, schema:, values:)
          config = config.is_a?(Hash) ? config : {}
          schema = schema.is_a?(Hash) ? schema : {}
          values = flatten(values)
          country = (values["country"] || schema["country"]).to_s.upcase
          errors = {}

          Array(config["fields"]).each do |field|
            next unless field.is_a?(Hash) && field["enabled"] == true

            key = field["key"].to_s
            only = Array(field["only_countries"]).map { |c| c.to_s.upcase }
            next if !only.empty? && !only.include?(country)
            next if hidden_by_schema?(key, schema)

            error = field_error(field, key, values[key], schema, country)
            errors[key] = error if error
          end
          { "valid" => errors.empty?, "fields" => errors }
        end

        private

        def flatten(values)
          values = values.is_a?(Hash) ? values : {}
          return values unless VALUE_GROUPS.any? { |group| values[group].is_a?(Hash) }

          flat = values.reject { |key, _| VALUE_GROUPS.include?(key) }
          VALUE_GROUPS.each { |group| flat.merge!(values[group]) if values[group].is_a?(Hash) }
          flat
        end

        def address_schema(schema, key)
          address = schema["address"].is_a?(Hash) ? schema["address"] : {}
          address[key].is_a?(Hash) ? address[key] : {}
        end

        def hidden_by_schema?(key, schema)
          key == "province" && address_schema(schema, "province")["mode"].to_s == "hidden"
        end

        def required?(field, key, schema)
          return field["required"] == true unless field["required"].nil?

          rules = address_schema(schema, key)
          case key
          when "zip" then rules["required"] == true
          when "province" then rules["mode"].to_s == "select" && rules["required"] != false
          when "city" then rules["required"] != false
          else false
          end
        end

        def error_key(key)
          SPECIFIC_ERRORS.include?(key) || key.start_with?("cf_") ? "error_#{key}" : "error_required"
        end

        def field_error(field, key, raw, schema, country)
          type = field["type"].to_s
          required = required?(field, key, schema)

          if %w[consent checkbox].include?(type)
            checked = raw == true || %w[true 1 on].include?(raw.to_s)
            return required && !checked ? error_key(key) : nil
          end

          value = raw.nil? ? "" : raw.to_s.strip
          if value.empty?
            return nil unless required

            return error_key(key)
          end

          return phone_error(value, country, schema) if type == "tel"
          return "error_email" if type == "email" && !value.match?(EMAIL)

          if type == "postal"
            regex = address_schema(schema, "zip")["regex"].to_s
            return "error_zip" if !regex.empty? && !matches?(regex, value)
          end
          if %w[select radio].include?(type)
            allowed = Array(field["options"]).map { |option| option.is_a?(Hash) ? option["value"].to_s : option.to_s }
            return error_key(key) unless allowed.empty? || allowed.include?(value)
          end
          return error_key(key) if type == "date" && !value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

          rules = field["validation"].is_a?(Hash) ? field["validation"] : {}
          return "error_latin_only" if rules["latin_only"] == true && !latin?(value)

          specific = SPECIFIC_ERRORS.include?(key) || key.start_with?("cf_") ? "error_#{key}" : "error_pattern"
          return specific if rules["min"].is_a?(Numeric) && value.length < rules["min"]
          return specific if rules["max"].is_a?(Numeric) && value.length > rules["max"]

          regex = rules["regex"].to_s
          return specific if !regex.empty? && !matches?(regex, value)

          nil
        end

        def phone_error(value, country, schema)
          phone = schema["phone"].is_a?(Hash) ? schema["phone"] : {}
          result = Phone.validate(raw: value, country: country, rules: phone.merge("dial_code" => schema["dial_code"]))
          case result["error"]
          when nil then nil
          when "too_short" then "error_phone_too_short"
          when "too_long" then "error_phone_too_long"
          when "bad_prefix" then "error_phone_prefix"
          else "error_phone"
          end
        end

        # A broken pattern never blocks a buyer; a pattern that runs too long counts as "no match".
        def matches?(source, value)
          Regexp.new(source, timeout: REGEX_TIMEOUT).match?(value)
        rescue RegexpError => e
          e.class.name != "Regexp::TimeoutError"
        end

        def latin?(value)
          value.each_char.all? { |char| !char.match?(/\p{L}/) || char.match?(/\p{Latin}/) }
        end
      end
    end
  end
end
