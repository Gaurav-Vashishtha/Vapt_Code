# frozen_string_literal: true

class BillingSnapshotBuilder
  attr_reader :shop, :plan, :setting, :twilio_pricing

  def initialize(shop:, plan:, setting:, twilio_pricing:)
    @shop = shop
    @plan = plan
    @setting = setting
    @twilio_pricing = twilio_pricing
  end

  def as_json(*)
    {
      plan_name: plan&.name,
      plan_price: plan_price,
      plan_price_source: plan_price_source,
      plan_currency: plan_currency,
      capped_amount: capped_amount,
      capped_balance_remaining: capped_balance_remaining,
      capped_used: capped_used,
      sms_rate: sms_rate,
      whatsapp_rate: whatsapp_rate,
      whatsapp_marketing_rate: whatsapp_marketing_rate,
      bsp_whatsapp_rate: bsp_whatsapp_rate,
      partial_payment_fee: partial_payment_fee,
      partial_fee_source: partial_fee_source
    }.compact
  end

  private

  def plan_currency
    if plan && plan.respond_to?(:currency) && plan.currency.present?
      plan.currency
    elsif shop&.currency.present?
      shop.currency
    else
      "USD"
    end
  end

  def capped_amount
    safe_float(recurring_charge&.capped_amount)
  end

  def capped_balance_remaining
    safe_float(recurring_charge&.balance_remaining)
  end

  def capped_used
    used = safe_float(recurring_charge&.balance_used)
    return used if used

    return unless capped_amount && capped_balance_remaining

    (capped_amount - capped_balance_remaining).round(2)
  end

  # Rates come from MessagePricing, the same rules DynamicChargeJob bills with.
  def sms_rate
    pricer.sms(shop, pricing_country_code) if pricing_country_code
  end

  # Utility rate (order confirmation / fulfilment / pre-order OTP).
  def whatsapp_rate
    pricer.whatsapp(shop, pricing_country_code, category: :utility) if pricing_country_code
  end

  # Marketing rate (COD verification, COD→prepaid, first purchase, abandoned cart).
  def whatsapp_marketing_rate
    pricer.whatsapp(shop, pricing_country_code, category: :marketing) if pricing_country_code
  end

  def bsp_whatsapp_rate
    pricer.bsp_whatsapp(shop) if shop
  end

  def pricer
    @pricer ||= MessagePricing.new(
      # The raw row, not the twilio_pricing payload: the payload's sms_price is already
      # Philippines-adjusted and MessagePricing applies that adjustment itself.
      pricings: TwilioPricing.where(country_code: pricing_country_code).index_by(&:country_code),
      charge_overrides: charge_override ? { shop.id => charge_override } : {}
    )
  end

  # Shop's own country row, else the US / IN / first-row fallback.
  def pricing_country_code
    return @pricing_country_code if defined?(@pricing_country_code)

    row = twilio_pricing.presence || fallback_pricing
    @pricing_country_code = row.is_a?(Hash) ? (row["country_code"] || row[:country_code]) : row&.country_code
  end

  def charge_override
    return @charge_override if defined?(@charge_override)

    @charge_override = shop&.shop_charge_override
  rescue ActiveRecord::StatementInvalid
    @charge_override = nil
  end

  def fallback_pricing
    return @fallback_pricing if defined?(@fallback_pricing)

    # Try US first, then IN, then any available pricing
    @fallback_pricing = TwilioPricing.find_by(country_code: "US") ||
                        TwilioPricing.find_by(country_code: "IN") ||
                        TwilioPricing.first
  end

  # The amount Shopify actually bills for the current subscription wins over
  # the Plan row's list price (promo pricing, legacy pricing, India pricing).
  def plan_price
    shopify_price = safe_float(recurring_charge&.price)
    return shopify_price if shopify_price && recurring_charge_matches_plan?

    safe_float(plan&.price)
  end

  def plan_price_source
    shopify_price = safe_float(recurring_charge&.price)
    shopify_price && recurring_charge_matches_plan? ? "shopify" : "plan"
  end

  # Charges are created with name == plan.name (PlansController#upgrade), so a
  # charge for a different plan (stale charge_id) must not be shown as this
  # plan's price.
  def recurring_charge_matches_plan?
    return false unless recurring_charge && plan

    status = recurring_charge.respond_to?(:status) ? recurring_charge.status.to_s : ""
    return false if status.present? && status != "active"

    charge_name = recurring_charge.respond_to?(:name) ? recurring_charge.name.to_s : ""
    charge_name.blank? || charge_name.casecmp?(plan.name.to_s)
  end

  def partial_payment_fee
    PartialTransactionFee.rate_for(shop, plan: plan, setting: setting).round(4)
  end

  def partial_fee_source
    PartialTransactionFee.custom_rate(setting) ? "custom" : "plan_default"
  end

  def recurring_charge
    return @recurring_charge if defined?(@recurring_charge)

    @recurring_charge =
      if shop&.charge_id.present?
        ShopifyAPI::RecurringApplicationCharge.find(shop.charge_id)
      end
  rescue StandardError => e
    Rails.logger.warn(
      "[BillingSnapshotBuilder] Failed to load recurring charge for shop #{shop&.id}: #{e.message}"
    )
    @recurring_charge = nil
  end

  def safe_float(value)
    return nil if value.nil?

    Float(value)
  rescue StandardError
    nil
  end
end
