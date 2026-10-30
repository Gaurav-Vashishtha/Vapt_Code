# frozen_string_literal: true

class BillingReferralLinkService
  APPROVED_BY = "Merchant billing (COD King app)"

  class << self
    def normalize_shop_domain(shopify_domain)
      shopify_domain.to_s.gsub(/\.myshopify\.com$/i, "").downcase
    end

    def status_for_shop(shop)
      return { linked: false } unless shop

      domain = normalize_shop_domain(shop.shopify_domain)
      rs = ReferralShop.where(shop_domain: domain).includes(:referral_partner).first
      return { linked: false } unless rs

      {
        linked: true,
        approved: rs.approved?,
        partner_name: rs.referral_partner.name
      }
    end
  end

  def initialize(shop:, referral_code:)
    @shop = shop
    @code = referral_code.to_s.strip
  end

  def apply
    return error(:blank_code, "Enter a referral code.") if @code.blank?
    return error(:no_shop, "Store could not be found.") unless @shop

    partner = ReferralPartner.active.find_by("LOWER(referral_code) = ?", @code.downcase)
    return error(:invalid_code, "That referral code was not found or the partner account is inactive.") unless partner

    domain = self.class.normalize_shop_domain(@shop.shopify_domain)
    existing = ReferralShop.where(shop_domain: domain).first

    if existing
      if existing.referral_partner_id != partner.id
        return error(:other_partner, "This store is already linked to a different referral partner.")
      end
      existing.approve!(APPROVED_BY) unless existing.approved?
      return ok(partner_name: partner.name)
    end

    rs = partner.referral_shops.build(shop_domain: domain, active: true)
    rs.save!
    rs.approve!(APPROVED_BY)
    ok(partner_name: partner.name)
  rescue ActiveRecord::RecordInvalid => e
    error(:validation, e.record.errors.full_messages.to_sentence)
  end

  def unlink
    return error(:no_shop, "Store could not be found.") unless @shop

    domain = self.class.normalize_shop_domain(@shop.shopify_domain)
    existing = ReferralShop.find_by(shop_domain: domain)
    return error(:not_linked, "This store is not linked to any referral partner.") unless existing

    existing.destroy!
    ok
  end

  private

  def ok(extra = {})
    { ok: true, **extra }
  end

  def error(key, message)
    { ok: false, error_key: key, message: message }
  end
end
