require "test_helper"

class CountryPlanOfferTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
    @shop.update_columns(country_code: "EG")
    @offer = CountryPlanOffer.create!(name: "EG founding", country_code: "eg", plan_name: "Enterprise",
                                      trial_days: 90, max_redemptions: 2, active: true)
  end

  test "finds the running offer for the shop's country and plan" do
    assert_equal @offer, CountryPlanOffer.for(@shop, "enterprise")
    assert_nil CountryPlanOffer.for(@shop, "Pro")
  end

  test "ignores other countries, inactive and ended offers" do
    @shop.update_columns(country_code: "PK")
    assert_nil CountryPlanOffer.for(@shop, "Enterprise")
    @shop.update_columns(country_code: "EG")
    @offer.update!(ends_at: 1.minute.ago)
    assert_nil CountryPlanOffer.for(@shop, "Enterprise")
  end

  test "approval uses a slot and the shop cannot use it again" do
    @shop.update_columns(charge_id: "123")
    CountryPlanOfferRedemption.record_pending!(@offer, @shop, "123")
    assert_equal 0, @offer.reload.redemptions_count
    CountryPlanOfferRedemption.activate_for!(@shop)
    assert_equal 1, @offer.reload.redemptions_count
    assert_nil CountryPlanOffer.for(@shop, "Enterprise")
  end

  test "stops when slots are used up" do
    @offer.update_columns(redemptions_count: 2)
    assert_nil CountryPlanOffer.for(@shop, "Enterprise")
  end

  test "needs a price or trial days" do
    offer = CountryPlanOffer.new(name: "x", country_code: "EG", plan_name: "Pro")
    assert_not offer.valid?
  end

  test "a store gets only one free trial across plans" do
    pro = CountryPlanOffer.create!(name: "EG trial", country_code: "EG", plan_name: "Pro", trial_days: 30, active: true)
    assert_equal pro, CountryPlanOffer.for(@shop, "Pro")
    @shop.update_columns(charge_id: "456")
    CountryPlanOfferRedemption.record_pending!(@offer, @shop, "456")
    CountryPlanOfferRedemption.activate_for!(@shop)
    assert_nil CountryPlanOffer.for(@shop, "Pro")
    assert_not CountryPlanOffer.display_for(@shop).key?("Pro")
  end
end
