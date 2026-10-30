# frozen_string_literal: true

require "test_helper"

class CodForm::ShippingRateTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  test "active.ordered returns active rates by position" do
    second = CodForm::ShippingRate.create!(shop: @shop, name: "Express", price_cents: 299_000, position: 2)
    first = CodForm::ShippingRate.create!(shop: @shop, name: "Standard", price_cents: 149_000, position: 1)
    CodForm::ShippingRate.create!(shop: @shop, name: "Off", position: 0, active: false)

    assert_equal [first.id, second.id], @shop.cod_shipping_rates.active.ordered.pluck(:id)
  end

  test "price is integer cents, zero means free" do
    rate = CodForm::ShippingRate.new(shop: @shop, name: "Free", currency: "huf")

    assert rate.valid?
    assert rate.free?
    assert_equal "HUF", rate.currency
    assert_equal "manual", rate.source

    rate.price_cents = -1
    assert_not rate.valid?
  end

  test "requires a name and a known source" do
    assert_not CodForm::ShippingRate.new(shop: @shop).valid?
    assert_not CodForm::ShippingRate.new(shop: @shop, name: "X", source: "shopify").valid?
  end
end
