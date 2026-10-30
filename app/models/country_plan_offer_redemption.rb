# frozen_string_literal: true

# One shop's use of a CountryPlanOffer. "pending" when the charge is created, "activated" (and the
# offer's slot count incremented) when the merchant approves it.
class CountryPlanOfferRedemption < ApplicationRecord
  belongs_to :country_plan_offer
  belongs_to :shop

  STATUSES = %w[pending activated].freeze
  validates :status, inclusion: { in: STATUSES }

  def self.record_pending!(offer, shop, charge_id)
    row = find_or_initialize_by(country_plan_offer_id: offer.id, shop_id: shop.id)
    return row if row.status == "activated"

    row.update!(charge_id: charge_id.to_s, status: "pending")
    row
  rescue StandardError => e
    Rails.logger.warn("[CountryPlanOffer] could not record redemption offer=#{offer&.id} shop=#{shop&.id} #{e.class}")
    nil
  end

  # Called after Shopify activates the shop's charge.
  def self.activate_for!(shop)
    return if shop.charge_id.blank?

    row = where(shop_id: shop.id, charge_id: shop.charge_id.to_s, status: "pending").first
    return unless row

    transaction do
      row.update!(status: "activated", activated_at: Time.current)
      CountryPlanOffer.where(id: row.country_plan_offer_id).update_all("redemptions_count = redemptions_count + 1")
    end
  rescue StandardError => e
    Rails.logger.warn("[CountryPlanOffer] could not activate redemption shop=#{shop&.id} #{e.class}")
  end
end
