# frozen_string_literal: true

module Ops
  # Approximate currency -> INR rates for dashboard totals only (never billing).
  # Override or extend with ENV OPS_FX_RATES='{"USD":86.5,"AED":23.6}'.
  # Currencies without a rate are reported separately, never silently dropped.
  module Fx
    DEFAULTS = {
      'INR' => 1.0, 'USD' => 88.0, 'EUR' => 96.0, 'GBP' => 112.0,
      'AED' => 24.0, 'SAR' => 23.5, 'EGP' => 1.8, 'QAR' => 24.2
    }.freeze

    def self.rates
      overrides = begin
        JSON.parse(ENV.fetch('OPS_FX_RATES', '{}'))
      rescue JSON::ParserError
        {}
      end
      DEFAULTS.merge(overrides.transform_values(&:to_f))
    end

    def self.to_inr(amount, currency, rates = self.rates)
      rate = rates[currency.to_s.upcase]
      rate ? amount.to_f * rate : nil
    end
  end
end
