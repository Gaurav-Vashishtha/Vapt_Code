# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineFeatureGatesTest < Minitest::Test
  include EngineTestHelper
  G = CodForm::Engine::FeatureGates

  def gates
    E::Defaults.feature_gates
  end

  def allowed?(key, tier, overrides = {}, rows = gates)
    G.allowed?(feature_key: key, tier: tier, gates: rows, overrides: overrides)
  end

  def test_seed_matches_the_product_table
    assert_equal 27, gates.length
    free = gates.select { |row| row["min_tier"] == "free" }.map { |row| row["feature_key"] }
    assert_includes free, "order_bumps"
    assert_includes free, "upsell"
    assert_equal %w[ab_tests], gates.select { |row| row["min_tier"] == "enterprise" }.map { |row| row["feature_key"] }
    assert_equal "pro", gates.find { |row| row["feature_key"] == "branding_removal" }["min_tier"]
    assert_equal "pro", gates.find { |row| row["feature_key"] == "address_autocomplete" }["min_tier"]
  end

  def test_tier_order
    assert allowed?("cod_form_core", "free")
    refute allowed?("rto_gating", "free")
    assert allowed?("rto_gating", "pro")
    assert allowed?("rto_gating", "enterprise_plus")
    refute allowed?("ab_tests", "pro")
    assert allowed?("ab_tests", "enterprise")
    refute allowed?("rto_gating", "mystery_tier")
  end

  def test_override_wins
    assert allowed?("ab_tests", "free", { "ab_tests" => true })
    refute allowed?("cod_form_core", "enterprise_plus", { "cod_form_core" => false })
  end

  def test_unknown_key_and_disabled_gate_are_denied
    refute allowed?("teleport", "enterprise_plus", { "teleport" => true })
    rows = gates.map { |row| row["feature_key"] == "upsell" ? row.merge("enabled" => false) : row }
    refute allowed?("upsell", "enterprise_plus", {}, rows)
    refute allowed?("upsell", "enterprise_plus", { "upsell" => true }, rows)
  end

  def test_map
    map = G.map(tier: "free", gates: gates, overrides: { "multiple_forms" => true })
    assert_equal({ "allowed" => true, "min_tier" => "free" }, map["quantity_offers"])
    assert_equal({ "allowed" => false, "min_tier" => "pro" }, map["threshold_offers"])
    assert_equal({ "allowed" => true, "min_tier" => "pro" }, map["multiple_forms"])
    assert_equal 27, map.length
  end
end
