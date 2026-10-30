# frozen_string_literal: true

module CodForm
  module Engine
    # Phone validation and normalisation per country, without Phonelib (ARCHITECTURE E.10, FRM-7).
    class Phone
      class << self
        # rules = the country's "phone" hash + "dial_code"
        #   {"dial_code"=>"36","min"=>8,"max"=>9,"strip_leading_zero"=>true,"trunk_prefixes"=>["06"],
        #    "mobile_prefixes"=>["20","30"],"enforce_mobile"=>false}
        # => {"valid"=>bool, "national"=>String, "e164"=>String, "digits"=>String,
        #     "error"=>nil|"too_short"|"too_long"|"bad_prefix"|"empty"}
        def validate(raw:, country: nil, rules: nil)
          rules = rules.is_a?(Hash) ? rules : {}
          rules = rules["phone"].merge("dial_code" => rules["dial_code"]) if rules["phone"].is_a?(Hash)
          dial = rules["dial_code"].to_s.gsub(/\D/, "")
          min = rules["min"].is_a?(Numeric) ? rules["min"].to_i : 6
          max = rules["max"].is_a?(Numeric) ? rules["max"].to_i : 14
          prefixes = Array(rules["mobile_prefixes"]).map(&:to_s).reject(&:empty?)

          text = raw.to_s.strip
          international = text.start_with?("+")
          digits = text.gsub(/\D/, "")
          return failure("empty") if digits.empty?

          explicit = false
          if international
            explicit = true
          elsif digits.start_with?("00") && !dial.empty?
            digits = digits[2..]
            explicit = true
          end

          national =
            if explicit
              # "+<dial>" / "00<dial>": the dial code must be this country's.
              return finish(digits, dial, "bad_prefix", digits) unless dial.empty? || digits.start_with?(dial)

              local(digits[dial.length..], rules)
            else
              plain = local(digits, rules)
              stripped = !dial.empty? && digits.start_with?(dial) ? local(digits[dial.length..], rules) : nil
              choose(plain, stripped, min, max, prefixes)
            end

          error =
            if national.empty? then "empty"
            elsif national.length < min then "too_short"
            elsif national.length > max then "too_long"
            elsif rules["enforce_mobile"] == true && !prefixes.empty? && prefixes.none? { |p| national.start_with?(p) }
              "bad_prefix"
            end
          finish(national, dial, error)
        end

        private

        # Removes the trunk prefix ("06" in Hungary) and leading zeros where the country uses them.
        def local(digits, rules)
          value = digits.to_s
          Array(rules["trunk_prefixes"]).map(&:to_s).reject(&:empty?).sort_by { |p| -p.length }.each do |prefix|
            if value.start_with?(prefix) && value.length > prefix.length
              value = value[prefix.length..]
              break
            end
          end
          value = value.sub(/\A0+/, "") if rules["strip_leading_zero"] == true
          value
        end

        # A leading bare dial code is stripped only when what remains is a plausible national number
        # and the unstripped number is not one already.
        def choose(plain, stripped, min, max, prefixes)
          return plain if stripped.nil?

          fits = ->(value) { value.length.between?(min, max) }
          mobile = ->(value) { prefixes.empty? || prefixes.any? { |p| value.start_with?(p) } }
          return plain if fits.call(plain) && mobile.call(plain)
          return stripped if fits.call(stripped)

          plain
        end

        def finish(national, dial, error, digits_override = nil)
          digits = digits_override || "#{dial}#{national}"
          { "valid" => error.nil?, "national" => digits_override ? "" : national, "e164" => "+#{digits}",
            "digits" => digits, "error" => error }
        end

        def failure(error)
          { "valid" => false, "national" => "", "e164" => "", "digits" => "", "error" => error }
        end
      end
    end
  end
end
