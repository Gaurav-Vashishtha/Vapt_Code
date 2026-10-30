# frozen_string_literal: true

# Data for the public /pricing page: every country's per-message rates on
# every plan, computed with the same rules billing uses (MessagePricing,
# PricingV3India, PartialTransactionFee), so the page can't drift from what
# merchants are actually charged.
class PublicPricingCatalog
  # Monthly plan prices, mirroring the in-app plans screens
  # (Plans.jsx for global stores, IndiaPlanPricingService for India).
  PLANS = [
    { key: 'free', name: 'Free', match: 'free', usd: 0.0, inr_key: nil },
    { key: 'pro', name: 'Pro', match: 'pro', usd: 9.99, inr_key: 'Pro' },
    { key: 'enterprise', name: 'Enterprise', match: 'enterprise', usd: 39.0, inr_key: 'india_budget' },
    { key: 'enterprise_plus', name: 'Enterprise Plus', match: 'enterprise plus', usd: 59.0, inr_key: 'Enterprise Plus' }
  ].freeze

  # Plans that can send WhatsApp from the merchant's own number (BSP).
  BSP_PLANS = %w[enterprise enterprise_plus].freeze

  def initialize(multiplier: 1.0)
    @multiplier = multiplier.to_f.positive? ? multiplier.to_f : 1.0
  end

  def countries
    rows = TwilioPricing.where.not(country_code: [nil, '']).order(:country).to_a
    rows.uniq { |r| r.country_code.to_s.upcase }.filter_map { |row| country(row) }
  end

  def updated_on
    TwilioPricing.maximum(:updated_at)&.to_date
  end

  private

  def country(row)
    code = row.country_code.to_s.upcase
    india = code == PricingV3India::COUNTRY_CODE && PricingV3India.applies_to_shop_id?(nil)
    plans = india ? india_plans : global_plans(row)
    return nil if plans.nil?

    {
      code: code,
      name: row.country.to_s.strip.presence || code,
      currency: india ? 'INR' : 'USD',
      plans: plans
    }
  end

  def global_plans(row)
    sms_base = PhilippinesSmsRate.effective_sms_base_usd(country_code: row.country_code, shop_id: nil,
                                                         db_sms_price: row.sms_price.to_f).to_f
    pricer = MessagePricing.new(pricings: { row.country_code => row })
    utility_base = pricer.whatsapp_base_usd(row.country_code, :utility)
    marketing_base = pricer.whatsapp_base_usd(row.country_code, :marketing)
    return nil if sms_base <= 0 && utility_base.nil? && marketing_base.nil?

    PLANS.map do |plan|
      sms_m = MessagePricing.sms_plan_multiplier(plan[:match])
      wa_m = MessagePricing.whatsapp_plan_multiplier(plan[:match])
      plan_row(plan,
               price: plan[:usd],
               sms: (sms_base * sms_m if sms_base.positive?),
               utility: (utility_base * wa_m if utility_base),
               marketing: (marketing_base * wa_m if marketing_base),
               bsp: MessagePricing::BSP_WHATSAPP_USD)
    end
  end

  # India (V3): flat INR rates — the Free plan has its own card, every paid
  # plan shares one card.
  def india_plans
    PLANS.map do |plan|
      rates = plan[:key] == 'free' ? PricingV3India::FREE_RATES_INR : PricingV3India::RATES_INR
      price = plan[:inr_key] ? IndiaPlanPricingService::PRICING.dig(plan[:inr_key], :rupees).to_f : 0.0
      plan_row(plan,
               price: price,
               sms: rates[:sms],
               utility: rates[:whatsapp_utility],
               marketing: rates[:whatsapp_marketing],
               bsp: MessagePricing::BSP_WHATSAPP_USD * PricingV3India.inr_per_usd)
    end
  end

  def plan_row(plan, price:, sms:, utility:, marketing:, bsp:)
    {
      key: plan[:key],
      name: plan[:name],
      price: price,
      sms: rate(sms),
      utility: rate(utility),
      marketing: rate(marketing),
      bsp: (rate(bsp) if BSP_PLANS.include?(plan[:key])),
      partial_fee: partial_fee(plan[:match])
    }
  end

  def rate(value)
    return nil if value.nil? || value.to_f <= 0

    (value.to_f * @multiplier).round(4)
  end

  def partial_fee(plan_match)
    (PartialTransactionFee.default_rate(nil, plan: Struct.new(:name).new(plan_match)) * 100).round(2)
  end
end
