# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineCapResolverTest < Minitest::Test
  include EngineTestHelper
  C = CodForm::Engine::CapResolver

  GLOBAL = { "at_cap_behaviour" => "fallback", "grace_orders" => 0 }.freeze
  GROUP_ID = 7

  # The J.2 seed, with the launch-market group stored under id 7.
  def seed
    E::Defaults.plan_limits.map do |row|
      row["scope_type"] == "country_group" ? row.reject { |key, _| key == "country_group" }.merge("scope_key" => GROUP_ID.to_s) : row
    end
  end

  def resolve(tier, groups: [], limits: seed, shop_id: 1, global: GLOBAL)
    C.resolve(limits: limits, shop_id: shop_id, tier: tier, country_group_ids: groups, global: global)
  end

  def state(resolved, orders)
    C.state(resolved: resolved, orders_count: orders)
  end

  def test_plan_defaults
    assert_equal({ "cap" => 60, "behaviour" => "grace", "grace_orders" => 10, "overage_rate" => nil, "source" => "plan" }, resolve("free"))
    assert_equal [500, "flag_only", 0], resolve("pro").values_at("cap", "behaviour", "grace_orders")
    assert_equal [10_000, "flag_only"], resolve("enterprise").values_at("cap", "behaviour")
    assert_equal [nil, "fallback", "plan"], resolve("enterprise_plus").values_at("cap", "behaviour", "source")
  end

  def test_free_plan_timeline_from_the_seed
    free = resolve("free")
    assert_equal({ "state" => "ok", "over_by" => 0, "percent" => 78 }, state(free, 47))
    assert_equal 80, state(free, 48)["percent"]                       # 80% notice
    assert_equal({ "state" => "ok", "over_by" => 0, "percent" => 98 }, state(free, 59))      # order 60 goes through
    assert_equal({ "state" => "grace", "over_by" => 0, "percent" => 100 }, state(free, 60))  # order 61 goes through (grace)
    assert_equal({ "state" => "grace", "over_by" => 1, "percent" => 101 }, state(free, 61))
    assert_equal({ "state" => "grace", "over_by" => 9, "percent" => 115 }, state(free, 69))  # order 70 goes through
    assert_equal({ "state" => "fallback", "over_by" => 10, "percent" => 116 }, state(free, 70)) # order 71 goes to checkout
    assert_equal "fallback", state(free, 71)["state"]
  end

  def test_paid_plans_are_only_flagged
    pro = resolve("pro")
    assert_equal "ok", state(pro, 499)["state"]
    assert_equal "flagged", state(pro, 500)["state"]
    assert_equal({ "state" => "flagged", "over_by" => 4500, "percent" => 1000 }, state(pro, 5000))
  end

  def test_unlimited
    plus = resolve("enterprise_plus")
    assert_equal({ "state" => "ok", "over_by" => 0, "percent" => nil }, state(plus, 1_000_000))
  end

  def test_launch_market_group_overrides_the_plan_on_every_tier
    free = resolve("free", groups: [GROUP_ID])
    assert_equal [nil, "country_group"], free.values_at("cap", "source")
    assert_equal "ok", state(free, 5000)["state"]
    assert_nil resolve("pro", groups: [GROUP_ID])["cap"]
    assert_equal 60, resolve("free", groups: [99])["cap"], "a group without rows does not match"
  end

  def test_shop_override_wins_and_inherits_behaviour_down_the_chain
    limits = seed + [{ "scope_type" => "shop", "scope_key" => "1", "monthly_cap" => 100, "at_cap_behaviour" => nil, "grace_orders" => nil, "active" => true }]
    shop = resolve("free", groups: [GROUP_ID], limits: limits)
    assert_equal [100, "grace", 10, "shop"], shop.values_at("cap", "behaviour", "grace_orders", "source")
    assert_equal "grace", state(shop, 109)["state"]
    assert_equal "fallback", state(shop, 110)["state"]
    assert_equal 60, resolve("free", limits: limits, shop_id: 2)["cap"]
  end

  def test_tier_specific_group_row_comes_before_the_tier_less_row
    limits = seed + [{ "scope_type" => "country_group", "scope_key" => GROUP_ID.to_s, "plan_tier" => "free", "monthly_cap" => 200, "active" => true }]
    assert_equal 200, resolve("free", groups: [GROUP_ID], limits: limits)["cap"]
    assert_nil resolve("pro", groups: [GROUP_ID], limits: limits)["cap"]
  end

  def test_groups_are_tried_in_the_given_order
    limits = seed + [{ "scope_type" => "country_group", "scope_key" => "8", "plan_tier" => nil, "monthly_cap" => 300, "active" => true }]
    assert_equal 300, resolve("free", groups: [8, GROUP_ID], limits: limits)["cap"]
    assert_nil resolve("free", groups: [GROUP_ID, 8], limits: limits)["cap"]
  end

  def test_inactive_rows_are_ignored_and_global_is_the_last_resort
    inactive = seed.map { |row| row["scope_type"] == "country_group" ? row.merge("active" => false) : row }
    assert_equal 60, resolve("free", groups: [GROUP_ID], limits: inactive)["cap"]
    bare = [{ "scope_type" => "plan", "scope_key" => "free", "monthly_cap" => 5, "active" => true }]
    resolved = resolve("free", limits: bare, global: { "at_cap_behaviour" => "grace", "grace_orders" => 2 })
    assert_equal ["grace", 2], resolved.values_at("behaviour", "grace_orders")
    assert_equal "grace", state(resolved, 6)["state"]
    assert_equal "fallback", state(resolved, 7)["state"]
    fallback = resolve("free", limits: bare)
    assert_equal "ok", state(fallback, 4)["state"]
    assert_equal "fallback", state(fallback, 5)["state"]
    assert_equal [nil, "none"], resolve("free", limits: []).values_at("cap", "source")
  end

  def test_overage_rate_is_inherited
    limits = seed.map { |row| row["scope_key"] == "pro" ? row.merge("overage_rate" => "0.05") : row }
    assert_equal "0.05", resolve("pro", limits: limits)["overage_rate"]
    assert_nil resolve("pro")["overage_rate"]
  end
end
