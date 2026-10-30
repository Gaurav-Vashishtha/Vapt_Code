# frozen_string_literal: true

# Returns dynamic pricing for India plans (Pro, india_budget, Enterprise Plus).
# Current plan: price from Shopify recurring charge. Other plans: always new pricing.
class IndiaPlanPricingService
  INDIA_PLANS = ["Pro", "india_budget", "Enterprise Plus"].freeze

  # New pricing (used for non-current plans and when creating a new subscription)
  PRICING = {
    "Pro" => { usd: 9.99, rupees: 899, usd_display: "$9.99 USD" },
    "india_budget" => { usd: 21.99, rupees: 1999, usd_display: "$21.99 USD" },
    "Enterprise Plus" => { usd: 59.0, rupees: 4999, usd_display: "$59 USD" }
  }.freeze

  # Approx USD to INR for display (e.g. Shopify charge is in USD)
  USD_TO_INR = 90.0

  # Limited-time promo (see SubscriptionOffer). India shows ₹1; the actual charge
  # amount is shared across countries.
  OFFER_RUPEES = 1
  OFFER_USD = SubscriptionOffer::CHARGE_USD

  def initialize(shop)
    @shop = shop
  end

  def offer_for_shop?
    SubscriptionOffer.eligible?(@shop)
  end

  # USD amount to use when creating a new recurring charge. Always new price.
  def charge_price_usd(plan_name)
    return nil unless INDIA_PLANS.include?(plan_name.to_s)
    return OFFER_USD if offer_for_shop?

    PRICING.dig(plan_name.to_s, :usd)
  end

  # Display pricing for one plan. recurring_charge = ShopifyAPI charge for current plan when available.
  def display_pricing_for_plan(plan_name, recurring_charge: nil)
    return nil unless INDIA_PLANS.include?(plan_name.to_s)
    key = plan_name.to_s
    current_plan_name = @shop.plan&.name&.to_s
    is_current_plan = current_plan_name.present? &&
                      current_plan_name.downcase == key.downcase &&
                      @shop.charge_id.present?

    if offer_for_shop?
      return {
        plan_key: key,
        rupees: OFFER_RUPEES,
        rupees_display: "₹1",
        usd: OFFER_USD,
        usd_display: format("$%.2f USD", OFFER_USD),
        is_current_plan: is_current_plan,
        charge_price_usd: OFFER_USD,
        limited_time_offer: true,
        original_rupees_display: format_rupees(PRICING.dig(key, :rupees)),
        original_usd_display: PRICING.dig(key, :usd_display)
      }
    end

    if is_current_plan && recurring_charge&.respond_to?(:price)
      actual_usd = recurring_charge.price.to_f
      approx_rupees = (actual_usd * USD_TO_INR).round
      rupees = approx_rupees
      rupees_display = format_rupees(approx_rupees)
      usd_display = format("$%.2f USD", actual_usd)
    else
      rupees = PRICING.dig(key, :rupees)
      rupees_display = format_rupees(rupees)
      usd_display = PRICING.dig(key, :usd_display)
    end

    {
      plan_key: key,
      rupees: rupees,
      rupees_display: rupees_display,
      usd: is_current_plan && recurring_charge&.respond_to?(:price) ? recurring_charge.price.to_f : PRICING.dig(key, :usd),
      usd_display: usd_display,
      is_current_plan: is_current_plan,
      charge_price_usd: PRICING.dig(key, :usd)
    }
  end

  # Display pricing for all India plans. Fetches Shopify recurring charge when shop has one.
  def all_display_pricing(fetch_shopify_charge: true)
    recurring_charge = nil
    if fetch_shopify_charge && @shop.charge_id.present?
      begin
        @shop.init_session
        recurring_charge = ShopifyAPI::RecurringApplicationCharge.find(@shop.charge_id)
      rescue StandardError => e
        Rails.logger.warn("[IndiaPlanPricingService] Could not fetch recurring charge: #{e.message}")
      end
    end

    INDIA_PLANS.map { |name| display_pricing_for_plan(name, recurring_charge: recurring_charge) }.compact
  end

  private

  def format_rupees(amount)
    return "₹0" if amount.blank? || amount.zero?
    return "₹#{amount}" if amount < 1000
    "₹#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
  end
end
