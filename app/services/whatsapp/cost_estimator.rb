module Whatsapp
  # Meta's per-message rates for India, effective 2026-01-01, excluding 18% GST.
  # Meta bills the merchant's WhatsApp account directly; COD King adds nothing.
  module CostEstimator
    module_function

    DEFAULT_COUNTRY = 'IN'.freeze
    DEFAULT_CATEGORY = 'MARKETING'.freeze

    RATES = {
      'IN' => { 'MARKETING' => BigDecimal('0.8631'), 'UTILITY' => BigDecimal('0.115'), currency: 'INR' }
    }.freeze

    def estimate(count:, category: DEFAULT_CATEGORY, country: DEFAULT_COUNTRY)
      country = RATES.key?(country.to_s.upcase) ? country.to_s.upcase : DEFAULT_COUNTRY
      category = category.to_s.upcase
      category = DEFAULT_CATEGORY unless RATES[country].key?(category)
      rate = rate_for(country, category)
      count = [count.to_i, 0].max

      {
        amount: (rate * count).round(2),
        currency: RATES[country][:currency],
        rate: rate,
        category: category,
        country: country,
        count: count,
        excludes_gst: true
      }
    end

    def rate_for(country, category)
      override = ENV.fetch("WHATSAPP_MARKETING_RATE", nil).to_s.strip
      if country == 'IN' && category == 'MARKETING' && override.present?
        value = BigDecimal(override, exception: false)
        return value if value&.positive?
      end
      RATES[country][category]
    end
  end
end
