# frozen_string_literal: true

# Limited-time promo: when FREE_SUBSCRIPTION_OFFER is set, every paid plan is
# offered at a near-zero price (both displayed and actually charged) for
# eligible shops in any country. FREE_SUBSCRIPTION_OFFER_MIN_SHOP_ID grandfathers
# old shops out of the promo.
module SubscriptionOffer
  module_function

  CHARGE_USD = 0.01

  def active?
    value = ENV.fetch("FREE_SUBSCRIPTION_OFFER", nil).to_s.strip.downcase
    value.present? && !%w[0 false no off].include?(value)
  end

  def eligible?(shop)
    return false unless active?
    return false if shop.nil?
    return false if shop.try(:visible_plans).present?

    min = ENV.fetch("FREE_SUBSCRIPTION_OFFER_MIN_SHOP_ID", nil).to_s.strip
    return true if min.blank?

    shop.id.to_i >= min.to_i
  end

  def charge_display
    format("$%.2f USD", CHARGE_USD)
  end
end
