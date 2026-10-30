# frozen_string_literal: true

# shop_charge_overrides — support-team override of what a shop pays per WhatsApp message.
# Read by MessagePricing (used by PricingJobs::DynamicChargeJob): the normal price of a
# WhatsApp message (MSG91 plan-tier or India V3 rate, or the flat BSP commission) is
# multiplied by the multiplier of its category. nil = no override for that category;
# 1.0 = unchanged; 0 = free.
# whatsapp_bsp_commission_usd is not a multiplier: when set, every BSP message is charged
# exactly that many USD, and the multipliers no longer apply to BSP messages.
class ShopChargeOverride < ApplicationRecord
  MAX_MULTIPLIER = 10
  MAX_BSP_COMMISSION_USD = 1

  # Presence and existence are checked by shop_exists (one clear "Shop ID" error, no join query).
  belongs_to :shop, optional: true

  validates :shop_id, presence: true, uniqueness: true
  validates :whatsapp_utility_multiplier, :whatsapp_marketing_multiplier,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_MULTIPLIER },
            allow_nil: true
  validates :whatsapp_bsp_commission_usd,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_BSP_COMMISSION_USD },
            allow_nil: true
  validate :shop_exists

  def shop_domain
    shop&.shopify_domain
  end

  # Multiplier for a WhatsApp message category (:utility / :marketing), or nil.
  def whatsapp_multiplier_for(category)
    value = category.to_s == "marketing" ? whatsapp_marketing_multiplier : whatsapp_utility_multiplier
    value&.to_f
  end

  def bsp_commission_usd
    whatsapp_bsp_commission_usd&.to_f
  end

  # The job looks up every shop it charges; one query per shop, cached per job run by the caller.
  def self.for_shop_id(shop_id)
    find_by(shop_id: shop_id)
  end

  private

  def shop_exists
    return if shop_id.blank?

    errors.add(:shop_id, "does not match any shop") unless Shop.exists?(id: shop_id)
  end
end
