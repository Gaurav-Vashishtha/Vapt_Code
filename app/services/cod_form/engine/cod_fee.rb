# frozen_string_literal: true

unless defined?(::Rails)
  require_relative "money"
end

module CodForm
  module Engine
    # COD fee (ARCHITECTURE E.8, FEE-1, FEE-2). The only fee on form orders.
    class CodFee
      DEFAULT_LABEL = "Cash on delivery fee"
      # Currencies conventionally shown without decimals: a converted fixed fee is rounded to the unit.
      UNIT_ROUNDED = %w[HUF COP RSD PKR JPY KRW CLP].freeze

      class << self
        # config = {"enabled","mode"=>"fixed"|"percentage","value","label","taxable","fx_rate"} (+ optional "currency")
        # base_cents = merchandise total after discounts + shipping.
        # => {"enabled"=>bool,"label"=>String,"amount_cents"=>Integer,"taxable"=>bool}
        def compute(config:, base_cents:, currency: nil)
          config = config.is_a?(Hash) ? config : {}
          currency = config["currency"] if currency.nil?
          label = config["label"].to_s.strip
          label = DEFAULT_LABEL if label.empty?
          taxable = config["taxable"] == true
          off = { "enabled" => false, "label" => label, "amount_cents" => 0, "taxable" => taxable }
          value = number(config["value"])
          return off unless config["enabled"] == true && value && value.positive?

          amount =
            if config["mode"].to_s == "percentage"
              Money.round_to_half_unit(Money.percent_of([base_cents.to_i, 0].max, value))
            else
              rate = number(config["fx_rate"])
              rate = Rational(1) if rate.nil? || !rate.positive?
              cents = (value * 100 * rate + Rational(1, 2)).floor
              cents = ((Rational(cents) / 100 + Rational(1, 2)).floor) * 100 if rate != 1 && UNIT_ROUNDED.include?(currency.to_s.upcase)
              cents
            end
          return off unless amount.positive?

          { "enabled" => true, "label" => label, "amount_cents" => amount, "taxable" => taxable }
        end

        private

        def number(value)
          case value
          when Integer, Rational then Rational(value)
          when Float then Rational(value.to_s)
          when String then value.strip.match?(/\A-?\d+(\.\d+)?\z/) ? Rational(value.strip) : nil
          end
        end
      end
    end
  end
end
