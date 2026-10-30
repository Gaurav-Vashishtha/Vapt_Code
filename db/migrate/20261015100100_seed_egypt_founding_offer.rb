# frozen_string_literal: true

# Egypt founding merchants: Enterprise free for 1 month (30 days), then the normal price, first 25 stores.
# COD Form orders are already unlimited for Egypt (Launch markets country group).
# Created INACTIVE: test one upgrade on a development store first, then tick Active in
# /admin/country_plan_offers.
class SeedEgyptFoundingOffer < ActiveRecord::Migration[7.2]
  class Offer < ActiveRecord::Base
    self.table_name = "country_plan_offers"
  end

  def up
    return if Offer.exists?(country_code: "EG", plan_name: "Enterprise", name: "EG founding merchants")

    Offer.create!(name: "EG founding merchants", country_code: "EG", plan_name: "Enterprise",
                  price_usd: nil, trial_days: 30, max_redemptions: 25, active: false,
                  ends_at: Time.utc(2026, 12, 31, 23, 59), badge: "عرض المؤسسين: شهر مجاناً",
                  note: "Egypt campaign Oct 2026. 30 free days, then the Enterprise price; messages billed as usual.")
  end

  def down
    Offer.where(country_code: "EG", plan_name: "Enterprise", name: "EG founding merchants").delete_all
  end
end
