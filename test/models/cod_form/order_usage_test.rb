# frozen_string_literal: true

require "test_helper"

class CodForm::OrderUsageTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  test "increment! creates the row, then adds to it, and returns the new count" do
    assert_equal 1, CodForm::OrderUsage.increment!(shop_id: @shop.id, period: "2026-10", column: :orders_count)
    assert_equal 2, CodForm::OrderUsage.increment!(shop_id: @shop.id, period: "2026-10")
    assert_equal 1, CodForm::OrderUsage.increment!(shop_id: @shop.id, period: "2026-10", column: :test_orders_count)
    assert_equal 1, CodForm::OrderUsage.increment!(shop_id: @shop.id, period: "2026-11")

    usage = CodForm::OrderUsage.for(@shop.id, "2026-10")
    assert usage.persisted?
    assert_equal 2, usage.orders_count
    assert_equal 1, usage.test_orders_count
    assert_equal 0, usage.partial_orders_count
    assert_equal 2, CodForm::OrderUsage.where(shop_id: @shop.id).count
  end

  test "increment! refuses unknown columns and malformed periods" do
    assert_raises(ArgumentError) { CodForm::OrderUsage.increment!(shop_id: @shop.id, period: "2026-10", column: :cap_snapshot) }
    assert_raises(ArgumentError) { CodForm::OrderUsage.increment!(shop_id: @shop.id, period: "2026-13") }
  end

  test "for returns an unsaved zero row when nothing was counted" do
    usage = CodForm::OrderUsage.for(@shop.id, "2026-09")

    assert usage.new_record?
    assert_equal 0, usage.orders_count
    assert_equal 0, CodForm::OrderUsage.count
  end
end
