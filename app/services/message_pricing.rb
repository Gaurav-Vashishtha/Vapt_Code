# frozen_string_literal: true

# Per-message price rules for usage billing. PricingJobs::DynamicChargeJob bills
# with these, and the preview job, the billing page snapshot and the public
# pricing page read the same rules so the numbers can't drift apart.
#
# BSP WhatsApp (merchant's own number via Meta Cloud API): Meta bills the
# merchant directly and we only take a commission, so every message costs
# BSP_WHATSAPP_USD, whatever the country, plan (Rabbit included) or category.
# A ShopChargeOverride row is the only exception.
#
# MSG91 WhatsApp (COD King's number): the twilio_pricings column for the
# message's category (whatsapp_utility / whatsapp_marketing), falling back to
# the `whatsapp` column, times the shop's WhatsApp plan multiplier. India V3
# shops keep their flat INR rates (PricingV3India) as an exception.
#
# SMS: sms_price times the SMS plan multiplier.
#
# SMS: shop.charge_multiplier, when set, replaces the SMS plan multiplier.
# WhatsApp ignores shop.charge_multiplier; per-shop WhatsApp pricing is set only
# through ShopChargeOverride, applied on top of the plan multiplier.
class MessagePricing
  BSP_WHATSAPP_USD = 0.001

  # MSG91 TwilioLog ver_types billed at the marketing rate (COD-to-prepaid and
  # first-purchase nudges). `WHATSAPP` is COD verification, a utility template,
  # so it bills at the utility rate (as PricingV3India already does); the
  # prepaid-order, branded and Gupshup sends that share the type follow it.
  # Abandoned-cart WhatsApp is marketing and pre-order OTP WhatsApp is utility;
  # their callers pass the category directly.
  MARKETING_TWILIO_VER_TYPES = %w[WHATSAPP_COD_PREPAID WHATSAPP_FIRST_PURCHASE].freeze
  UTILITY_TWILIO_VER_TYPES = %w[WHATSAPP WHATSAPP-CONFIRMATION WHATSAPP-FULFILMENT].freeze
  WHATSAPP_TWILIO_VER_TYPES = (MARKETING_TWILIO_VER_TYPES + UTILITY_TWILIO_VER_TYPES).freeze

  # Matched as substrings because custom plans carry these words in their names.
  # Checked in this order, so a name containing "pro" is Pro even if it also
  # says enterprise.
  WHATSAPP_PLAN_MULTIPLIERS = [
    ['pro', 0.8],
    ['india_budget', 0.6],
    ['enterprise', 0.6],
    ['premium', 0.6]
  ].freeze

  class << self
    def whatsapp_category_for_ver_type(ver_type)
      MARKETING_TWILIO_VER_TYPES.include?(ver_type.to_s) ? :marketing : :utility
    end

    def whatsapp_plan_multiplier(plan_name)
      name = plan_name.to_s.downcase
      match = WHATSAPP_PLAN_MULTIPLIERS.find { |keyword, _| name.include?(keyword) }
      match ? match.last : 1.0
    end

    def sms_plan_multiplier(plan_name)
      name = plan_name.to_s.downcase
      return 0.85 if name.include?('pro')
      return 0.30 if name.include?('india_budget') || (name.include?('enterprise') && name.include?('plus'))
      return 0.7 if name.include?('enterprise') || name.include?('premium')

      1.0
    end

    def load_charge_overrides
      return {} unless ShopChargeOverride.table_exists?

      ShopChargeOverride.all.index_by(&:shop_id)
    rescue StandardError => e
      Rails.logger.error "[MessagePricing] could not load shop_charge_overrides: #{e.class}: #{e.message}"
      {}
    end
  end

  # pricings: { country_code => TwilioPricing (or a Hash with the same keys) }
  # charge_overrides: { shop_id => ShopChargeOverride }
  def initialize(pricings:, charge_overrides: {})
    @pricings = pricings || {}
    @charge_overrides = charge_overrides || {}
  end

  # USD for one SMS, or nil when the country has no price.
  def sms(shop, country_code, num_segment = nil)
    v3_price = PricingV3India.charge_usd(
      shop: shop, country_code: country_code, mode: 'sms', num_segment: num_segment
    )
    return v3_price if v3_price

    row = @pricings[country_code]
    return nil unless row

    price = field(row, 'sms_price').to_f
    price = PhilippinesSmsRate.effective_sms_base_usd(
      country_code: country_code,
      shop_id: shop.id,
      db_sms_price: price
    )
    return nil if price <= 0

    price *= shop_multiplier(shop) || self.class.sms_plan_multiplier(plan_name(shop))
    price *= segments(num_segment, shop) if num_segment.present?
    price.round(4)
  rescue StandardError => e
    log_error('sms', shop, country_code, e)
    nil
  end

  # USD for one MSG91 WhatsApp message, or nil when the country has no price.
  # india_category lets the India V3 path keep its own category mapping.
  def whatsapp(shop, country_code, category:, india_category: category)
    v3_price = PricingV3India.charge_usd(
      shop: shop, country_code: country_code, mode: 'whatsapp', category: india_category
    )
    return apply_override(v3_price, shop, india_category) if v3_price

    base = whatsapp_base_usd(country_code, category)
    return nil unless base

    price = base * self.class.whatsapp_plan_multiplier(plan_name(shop))
    apply_override(price.round(4), shop, category)
  rescue StandardError => e
    log_error('whatsapp', shop, country_code, e)
    nil
  end

  # USD for one BSP WhatsApp message.
  def bsp_whatsapp(shop, category: nil)
    override = @charge_overrides[shop.id]
    commission = override&.bsp_commission_usd
    return commission.round(6) if commission

    apply_override(BSP_WHATSAPP_USD, shop, category)
  end

  # twilio_pricings rate for a category before any multiplier, or nil.
  def whatsapp_base_usd(country_code, category)
    row = @pricings[country_code]
    return nil unless row

    column = category.to_s == 'marketing' ? 'whatsapp_marketing' : 'whatsapp_utility'
    specific = field(row, column).to_f
    return specific if specific.positive?

    fallback = field(row, 'whatsapp').to_f
    fallback.positive? ? fallback : nil
  end

  private

  def apply_override(price, shop, category)
    return price if price.nil?

    override = @charge_overrides[shop.id]
    return price unless override

    multiplier = override.whatsapp_multiplier_for(category.to_s == 'marketing' ? :marketing : :utility)
    return price if multiplier.nil? || multiplier.negative?

    (price.to_f * multiplier).round(6)
  end

  def shop_multiplier(shop)
    value = shop.charge_multiplier.to_f
    value.positive? ? value : nil
  end

  def plan_name(shop)
    shop.plan&.name
  end

  def segments(num_segment, shop)
    case num_segment
    when Numeric
      num_segment.to_f
    when String
      return num_segment.to_f if num_segment.strip.match?(/\A\d*\.?\d+\z/)

      Rails.logger.warn "[MessagePricing] Invalid num_segment: '#{num_segment}' for shop #{shop.id}"
      1.0
    else
      Rails.logger.warn "[MessagePricing] Unexpected num_segment type: #{num_segment.class} for shop #{shop.id}"
      1.0
    end
  end

  # A pricing error leaves that one message unpriced instead of failing the whole billing run.
  def log_error(kind, shop, country_code, error)
    Rails.logger.error "[MessagePricing] #{kind} price failed for shop #{shop&.id} country=#{country_code}: #{error.class}: #{error.message}"
  end

  def field(row, key)
    row.is_a?(Hash) ? (row[key] || row[key.to_sym]) : row[key]
  end
end
