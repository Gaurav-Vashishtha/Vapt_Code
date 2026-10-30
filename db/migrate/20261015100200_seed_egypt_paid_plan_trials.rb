# frozen_string_literal: true

# Egypt: 30 free days on every paid plan (Pro, Enterprise, Enterprise Plus), no store limit.
# The 25-store "EG founding merchants" Enterprise offer has a lower id, so it is picked first
# while it has slots; after that, Enterprise falls back to the trial row here.
# Created INACTIVE: tick Active in /admin/country_plan_offers after a dev-store test.
class SeedEgyptPaidPlanTrials < ActiveRecord::Migration[7.2]
  class Offer < ActiveRecord::Base
    self.table_name = "country_plan_offers"
  end

  PLANS = ["Pro", "Enterprise", "Enterprise Plus"].freeze
  NAME = "EG 30-day free trial"

  def up
    PLANS.each do |plan|
      next if Offer.exists?(country_code: "EG", plan_name: plan, name: NAME)

      Offer.create!(name: NAME, country_code: "EG", plan_name: plan, price_usd: nil, trial_days: 30,
                    max_redemptions: nil, active: false, ends_at: Time.utc(2026, 12, 31, 23, 59),
                    badge: "شهر مجاناً", note: "Egypt campaign Oct 2026. 30 free days, then the normal price; messages billed as usual.")
    end
  end

  def down
    Offer.where(country_code: "EG", name: NAME).delete_all
  end
end
