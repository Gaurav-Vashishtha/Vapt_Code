# frozen_string_literal: true

require "bigdecimal"

module CodForm
  module Engine
    # Integer-cents arithmetic (ARCHITECTURE E.1). Every amount is an Integer,
    # amount x 100 in the buyer's presentment currency.
    class Money
      DEFAULT_FORMAT = {
        "template" => "{{amount}}", "decimals" => 2, "thousands" => ",", "decimal" => "."
      }.freeze

      class << self
        # Round half up. Exact (Rational) arithmetic, so 0.1-style floats never drift.
        def percent_of(cents, percent)
          value = rational(cents) * rational(percent) / 100
          round_half_up(value)
        end

        # Nearest 50 cents, half up (mirrors ((x * 2).round / 2.0) on decimal amounts).
        def round_to_half_unit(cents)
          round_half_up(rational(cents) / 50) * 50
        end

        # Largest-remainder split of total across weights; the parts always sum to total.
        def allocate(total_cents, weights)
          list = Array(weights).map { |w| [rational(w), Rational(0)].max }
          return [] if list.empty?

          total = total_cents.to_i
          sum = list.sum
          list = list.map { Rational(1) } if sum.zero?
          sum = list.sum
          exact = list.map { |w| Rational(total) * w / sum }
          parts = exact.map(&:floor)
          remainder = total - parts.sum
          order = exact.each_with_index.sort_by { |value, index| [-(value - value.floor), index] }
          order.first(remainder).each { |_value, index| parts[index] += 1 }
          parts
        end

        # 648640 => "6486.40"
        def to_decimal_string(cents)
          value = cents.to_i
          sign = value.negative? ? "-" : ""
          value = value.abs
          Kernel.format("%s%d.%02d", sign, value / 100, value % 100)
        end

        def clamp_non_negative(cents)
          value = cents.to_i
          value.negative? ? 0 : value
        end

        # format = {"template"=>"{{amount}} Ft","decimals"=>0,"thousands"=>" ","decimal"=>","}
        def format(cents, format = nil)
          fmt = DEFAULT_FORMAT.merge(format.is_a?(Hash) ? format : {})
          decimals = fmt["decimals"].to_i
          decimals = 0 if decimals.negative?
          value = cents.to_i
          sign = value.negative? ? "-" : ""
          scaled = round_half_up(Rational(value.abs) * (10**decimals) / 100)
          whole = scaled / (10**decimals)
          fraction = scaled % (10**decimals)
          text = group(whole.to_s, fmt["thousands"].to_s)
          text += fmt["decimal"].to_s + fraction.to_s.rjust(decimals, "0") if decimals.positive?
          template = fmt["template"].to_s
          template = "{{amount}}" unless template.include?("{{amount}}")
          template.gsub("{{amount}}") { sign + text }
        end

        private

        def rational(value)
          case value
          when Integer, Rational then Rational(value)
          when nil then Rational(0)
          else
            text = value.to_s.strip
            text =~ /\A-?\d+(\.\d+)?\z/ ? Rational(text) : Rational(BigDecimal(value.to_f.to_s).to_r)
          end
        end

        def round_half_up(value)
          (value + Rational(1, 2)).floor
        end

        def group(digits, separator)
          return digits if separator.empty?

          digits.reverse.scan(/\d{1,3}/).join(separator.reverse).reverse
        end
      end
    end
  end
end
