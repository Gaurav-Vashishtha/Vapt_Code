# frozen_string_literal: true

module CodForm
  module Engine
    # Postal code lists: exact codes, prefixes ("4000*") and numeric ranges ("1000-1999").
    # ARCHITECTURE E.2, RUL-2.
    class PostalMatcher
      SEPARATORS = /[,;\r\n]+/.freeze

      class << self
        # list: String ("110001, 4000*, 560001-560100") or Array<String>
        def parse(list)
          entries =
            case list
            when nil then []
            when Array then list.flat_map { |item| item.is_a?(Hash) ? [item] : item.to_s.split(SEPARATORS) }
            else list.to_s.split(SEPARATORS)
            end
          entries.map { |entry| entry.is_a?(Hash) ? entry : parse_entry(entry) }.compact
        end

        def match?(code, patterns)
          normalized = normalize(code)
          return false if normalized.empty?

          parse(patterns).any? { |pattern| pattern_match?(normalized, pattern) }
        end

        # Upper-case, spaces and hyphens removed.
        def normalize(code)
          code.to_s.upcase.gsub(/[\s\-]/, "")
        end

        private

        def parse_entry(raw)
          entry = raw.to_s.strip
          return nil if entry.empty?

          if entry.end_with?("*")
            return { "type" => "prefix", "value" => normalize(entry.delete("*")) }
          end

          if entry.include?("-")
            sides = entry.split("-", -1).map { |side| side.gsub(/\s/, "") }
            if sides.length == 2 && sides.all? { |side| side.match?(/\A\d+\z/) } && sides[0].length == sides[1].length
              from, to = sides
              from, to = to, from if from.to_i > to.to_i
              return { "type" => "range", "from" => from, "to" => to }
            end
          end

          value = normalize(entry)
          value.empty? ? nil : { "type" => "exact", "value" => value }
        end

        def pattern_match?(code, pattern)
          case pattern["type"]
          when "exact" then code == normalize(pattern["value"])
          when "prefix" then code.start_with?(normalize(pattern["value"]))
          when "range"
            from = pattern["from"].to_s
            to = pattern["to"].to_s
            # Same width as the bounds, so integer and string order agree (leading zeros kept).
            code.match?(/\A\d+\z/) && code.length == from.length && code.to_i.between?(from.to_i, to.to_i)
          else false
          end
        end
      end
    end
  end
end
