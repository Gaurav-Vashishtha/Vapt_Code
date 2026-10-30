# frozen_string_literal: true

require "test_helper"

class CodForm::DailyStatTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  test "one row per shop, date, dimension and value" do
    CodForm::DailyStat.create!(shop: @shop, stat_date: Date.new(2026, 10, 3), metrics: { "orders" => 4 })

    assert CodForm::DailyStat.new(shop: @shop, stat_date: Date.new(2026, 10, 3)).invalid?
    assert CodForm::DailyStat.new(shop: @shop, stat_date: Date.new(2026, 10, 3), dimension: "country", dimension_value: "HU").valid?
    assert CodForm::DailyStat.new(shop: @shop, stat_date: Date.new(2026, 10, 4), dimension: "city").invalid?
  end

  test "metric reads integers and defaults to zero" do
    stat = CodForm::DailyStat.new(metrics: { "orders" => 4, "revenue_cents" => 659_600 })

    assert_equal 4, stat.metric(:orders)
    assert_equal 659_600, stat.metric("revenue_cents")
    assert_equal 0, stat.metric(:closes)
  end
end
