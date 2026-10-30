# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineCodRulesTest < Minitest::Test
  include EngineTestHelper
  R = CodForm::Engine::CodRules

  ADDRESS = { "country" => "HU", "province" => "BU", "zip" => "1051" }.freeze
  CONTACT = { "phone_digits" => "36301234567", "email" => "anna@example.com" }.freeze

  def evaluate(rules, cart: nil, address: ADDRESS, contact: CONTACT, stage: "quote")
    cart ||= { "lines" => [line], "total_cents" => 199_900 }
    R.evaluate(rules: rules, cart: cart, address: address, contact: contact, stage: stage)
  end

  def test_no_rules_allows
    assert_equal({ "allowed" => true, "reasons" => [], "pending" => [] }, evaluate({}))
  end

  def test_country
    assert evaluate({ "allow_countries" => ["hu"] })["allowed"]
    assert_equal ["country_not_allowed"], evaluate({ "allow_countries" => ["CO"] })["reasons"]
  end

  def test_provinces
    assert evaluate({ "allow_provinces" => ["BU"] })["allowed"]
    assert evaluate({ "allow_provinces" => ["HU-BU"] })["allowed"]
    assert_equal ["province_not_allowed"], evaluate({ "allow_provinces" => ["PE"] })["reasons"]
    assert_equal ["province_not_allowed"], evaluate({ "deny_provinces" => ["bu"] })["reasons"]
    assert evaluate({ "deny_provinces" => ["PE"] })["allowed"]
  end

  def test_zip_lists_use_exact_prefix_and_range
    assert evaluate({ "allow_zips" => "1051, 2000*" })["allowed"]
    assert evaluate({ "allow_zips" => "1000-1999" })["allowed"]
    assert_equal ["zip_not_allowed"], evaluate({ "allow_zips" => "2000-2999" })["reasons"]
    assert_equal ["zip_not_allowed"], evaluate({ "deny_zips" => "10*" })["reasons"]
    assert evaluate({ "deny_zips" => "2000-2999; 9*" })["allowed"]
  end

  def test_missing_address_is_pending_before_submit
    result = evaluate({ "allow_zips" => "1051", "allow_provinces" => ["BU"], "allow_countries" => ["HU"] }, address: {})
    assert result["allowed"]
    assert_equal %w[country province zip], result["pending"]
    page = evaluate({ "deny_zips" => "1051" }, address: { "country" => "HU" }, stage: "page")
    assert page["allowed"]
    assert_equal ["zip"], page["pending"]
  end

  def test_missing_address_fails_allow_lists_at_submit
    result = evaluate({ "allow_zips" => "1051", "allow_provinces" => ["BU"] }, address: { "country" => "HU" }, stage: "submit")
    refute result["allowed"]
    assert_equal %w[province_not_allowed zip_not_allowed], result["reasons"]
    assert_equal [], result["pending"]
    assert evaluate({ "deny_zips" => "1051", "deny_provinces" => ["BU"] }, address: { "country" => "HU" }, stage: "submit")["allowed"]
  end

  def test_products_and_variants
    assert_equal ["product_not_allowed"], evaluate({ "deny_product_ids" => ["8111"] })["reasons"]
    assert evaluate({ "deny_product_ids" => "9999, 7777" })["allowed"]
    assert evaluate({ "allow_product_ids" => ["8111"] })["allowed"]
    assert_equal ["product_not_allowed"], evaluate({ "allow_product_ids" => ["9999"] })["reasons"]
    assert_equal ["product_not_allowed"], evaluate({ "deny_variant_ids" => [44_111] })["reasons"]
    cart = { "lines" => [line, line("product_id" => "8222")], "total_cents" => 1 }
    assert_equal ["product_not_allowed"], evaluate({ "allow_product_ids" => ["8111"] }, cart: cart)["reasons"]
  end

  def test_gift_cards
    cart = { "lines" => [line("gift_card" => true)], "total_cents" => 1 }
    assert_equal ["product_not_allowed"], evaluate({ "hide_gift_cards" => true }, cart: cart)["reasons"]
    assert evaluate({ "hide_gift_cards" => false }, cart: cart)["allowed"]
  end

  def test_collections
    assert_equal ["collection_not_allowed"], evaluate({ "deny_collection_ids" => ["301"] })["reasons"]
    assert evaluate({ "allow_collection_ids" => ["301", "302"] })["allowed"]
    cart = { "lines" => [line, line("collection_ids" => ["999"])], "total_cents" => 1 }
    assert_equal ["collection_not_allowed"], evaluate({ "allow_collection_ids" => ["301"] }, cart: cart)["reasons"]
  end

  def test_vendors
    assert_equal ["vendor_not_allowed"], evaluate({ "deny_vendors" => ["acm"] })["reasons"] # contains
    assert evaluate({ "deny_vendors" => ["other"] })["allowed"]
    assert evaluate({ "allow_vendors" => ["ACME"] })["allowed"]
    assert_equal ["vendor_not_allowed"], evaluate({ "allow_vendors" => ["acm"] })["reasons"] # equals, not contains
    cart = { "lines" => [line, line("vendor" => "Other")], "total_cents" => 1 }
    assert evaluate({ "allow_vendors" => ["acme"] }, cart: cart)["allowed"] # at least one line
  end

  def test_total_range_bounds_are_inclusive_and_non_positive_bounds_ignored
    assert evaluate({ "min_total_cents" => 199_900, "max_total_cents" => 199_900 })["allowed"]
    assert_equal ["total_out_of_range"], evaluate({ "min_total_cents" => 199_901 })["reasons"]
    assert_equal ["total_out_of_range"], evaluate({ "max_total_cents" => 199_899 })["reasons"]
    assert evaluate({ "min_total_cents" => 0, "max_total_cents" => 0 })["allowed"]
    assert evaluate({ "min_total_cents" => nil, "max_total_cents" => -5 })["allowed"]
  end

  def test_buyer_block_lists
    assert_equal ["phone_blocked"], evaluate({ "deny_phones" => ["301234567"] })["reasons"]
    assert_equal ["phone_blocked"], evaluate({ "deny_phones" => "+36 30 123 4567" })["reasons"]
    assert evaluate({ "deny_phones" => ["999"] })["allowed"]
    assert_equal ["email_blocked"], evaluate({ "deny_emails" => ["@EXAMPLE.com"] })["reasons"]
    assert evaluate({ "deny_emails" => ["other.com"] })["allowed"]
  end

  def test_reasons_are_unique_and_combined
    result = evaluate({ "deny_product_ids" => ["8111"], "deny_variant_ids" => ["44111"], "allow_countries" => ["CO"] })
    assert_equal %w[country_not_allowed product_not_allowed], result["reasons"]
  end
end
