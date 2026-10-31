# frozen_string_literal: true

module PricingV3India
  COUNTRY_CODE = "IN"
  DEFAULT_INR_PER_USD = 95.0
  RATES_INR = {
    sms: 0.30,
    whatsapp_utility: 0.25,
    whatsapp_marketing: 1.10
  }.freeze
  FREE_RATES_INR = {
    sms: 1.0,
    whatsapp_utility: 0.60,
    whatsapp_marketing: 1.60
  }.freeze
  MARKETING_EVENT_KEYS = %w[
    abandoned_cart
    cart_abandoned
    browse_abandoned
    first_time_purchase
    cod_to_prepaid
    inbox_template_marketing
  ].freeze
  MARKETING_TWILIO_VER_TYPES = %w[WHATSAPP_FIRST_PURCHASE WHATSAPP_COD_PREPAID].freeze

  module_function

  def min_shop_id
    ENV.fetch("V3_PRICING_INDIA_MIN_SHOP_ID", nil).presence&.to_i
  end

  def inr_per_usd
    rate = ENV.fetch("V3_PRICING_INDIA_INR_PER_USD", nil).to_f
    rate.positive? ? rate : DEFAULT_INR_PER_USD
  end

  def applies_to_shop_id?(shop_id)
    min = min_shop_id
    return false if min.nil?
    return true if shop_id.blank?

    shop_id.to_i >= min
  end

  def applies_to_shop?(shop)
    shop.present? && shop.country_code.to_s.upcase == COUNTRY_CODE && applies_to_shop_id?(shop.id)
  end

  def paid_plan?(shop)
    plan = shop.plan
    return false if plan.nil?
    return false if plan.name.to_s.downcase.include?("rabbit")

    plan.price.to_f.positive?
  end

  def free_plan?(shop)
    plan = shop.plan
    return false if plan.nil?
    return false if plan.name.to_s.downcase.include?("rabbit")

    plan.price.to_f.zero?
  end

  def rates_for(shop)
    free_plan?(shop) ? FREE_RATES_INR : RATES_INR
  end

  def charged_by_v3?(shop, country_code)
    country_code.to_s.upcase == COUNTRY_CODE && applies_to_shop?(shop) &&
      (paid_plan?(shop) || free_plan?(shop))
  end

  def whatsapp_category_for_event(event_type_key)
    MARKETING_EVENT_KEYS.include?(event_type_key.to_s) ? :marketing : :utility
  end

  def whatsapp_category_for_ver_type(ver_type)
    MARKETING_TWILIO_VER_TYPES.include?(ver_type.to_s) ? :marketing : :utility
  end

  def rate_inr(kind, rates = RATES_INR)
    rates.fetch(kind)
  end

  def rate_usd(kind, rates = RATES_INR)
    (rate_inr(kind, rates) / inr_per_usd).round(6)
  end

  def whatsapp_kind(category)
    category.to_s == "marketing" ? :whatsapp_marketing : :whatsapp_utility
  end

  def charge_usd(shop:, country_code:, mode:, category: nil, num_segment: nil)
    return nil unless charged_by_v3?(shop, country_code)

    rates = rates_for(shop)
    if mode.to_s == "sms"
      (rate_usd(:sms, rates) * segments_from(num_segment)).round(6)
    else
      rate_usd(whatsapp_kind(category), rates)
    end
  end

  def segments_from(num_segment)
    value = num_segment.to_s.strip
    return 1.0 unless value.match?(/\A\d*\.?\d+\z/)

    value.to_f.positive? ? value.to_f : 1.0
  end

  def display_rates(rates = RATES_INR)
    rates.transform_values { |inr| format_inr(inr) }
  end

  def format_inr(amount)
    amount < 1 ? "#{(amount * 100).round} paise" : format("₹%.2f", amount)
  end
end
