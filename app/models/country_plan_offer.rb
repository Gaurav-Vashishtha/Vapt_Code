# frozen_string_literal: true

# A plan offer for one country: price_usd replaces the plan's monthly price on the Shopify charge,
# trial_days adds free days before billing starts (Shopify then bills the price automatically,
# no re-approval). The slot count only moves when the charge is approved (ChargeActivatedJob).
class CountryPlanOffer < ApplicationRecord
  has_many :redemptions, class_name: "CountryPlanOfferRedemption", dependent: :restrict_with_error

  validates :name, :country_code, :plan_name, presence: true
  validates :country_code, format: { with: /\A[A-Z]{2}\z/, message: "must be a 2-letter code like EG" }
  validates :price_usd, numericality: { greater_than_or_equal_to: 0.01 }, allow_nil: true
  validates :trial_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 365 }, allow_nil: true
  validates :max_redemptions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :changes_something

  before_validation { self.country_code = country_code.to_s.strip.upcase.presence }

  scope :running, lambda {
    now = Time.current
    where(active: true)
      .where("starts_at IS NULL OR starts_at <= ?", now)
      .where("ends_at IS NULL OR ends_at > ?", now)
      .where("max_redemptions IS NULL OR redemptions_count < max_redemptions")
  }

  class << self
    # The running offer for this shop's country and plan, unless the shop already used it.
    def for(shop, plan_name)
      return nil if shop.nil? || plan_name.blank? || shop.country_code.blank?

      running.where(country_code: shop.country_code.to_s.upcase)
             .where("LOWER(plan_name) = ?", plan_name.to_s.downcase)
             .order(:id)
             .find { |offer| !offer.used_by?(shop) && !(offer.trial_days && trial_used_by?(shop)) }
    rescue ActiveRecord::StatementInvalid
      nil # table not migrated yet
    end

    # One free trial per store: once any trial offer has been activated, switching plans gets no new trial.
    def trial_used_by?(shop)
      CountryPlanOfferRedemption.joins(:country_plan_offer)
                                .where(shop_id: shop.id, status: "activated")
                                .where.not(country_plan_offers: { trial_days: nil })
                                .exists?
    end

    # {"Enterprise" => {...}} for the plan cards.
    def display_for(shop)
      return {} if shop.nil? || shop.country_code.blank?

      running.where(country_code: shop.country_code.to_s.upcase).order(:id).each_with_object({}) do |offer, out|
        next if out.key?(offer.plan_name) || offer.used_by?(shop) || (offer.trial_days && trial_used_by?(shop))

        out[offer.plan_name] = offer.display
      end
    rescue ActiveRecord::StatementInvalid
      {}
    end
  end

  def used_by?(shop)
    redemptions.where(shop_id: shop.id, status: "activated").exists?
  end

  def slots_left
    max_redemptions && [max_redemptions - redemptions_count, 0].max
  end

  def display
    { "price_usd" => price_usd&.to_f, "trial_days" => trial_days, "badge" => badge, "slots_left" => slots_left }
  end

  private

  def changes_something
    errors.add(:base, "Set a price, trial days, or both") if price_usd.nil? && trial_days.nil?
  end
end
