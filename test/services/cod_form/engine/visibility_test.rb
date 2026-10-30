# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineVisibilityTest < Minitest::Test
  include EngineTestHelper
  V = CodForm::Engine::Visibility

  def evaluate(overrides = {}, cart: nil, country: "HU", page: "product")
    cart ||= { "lines" => [line], "total_cents" => 199_900 }
    V.evaluate(general: E::Defaults.general.merge(overrides), cart: cart, country: country, page: page)
  end

  def test_defaults_are_visible
    assert_equal({ "visible" => true, "reasons" => [], "message" => nil }, evaluate)
  end

  def test_countries
    assert evaluate({ "countries" => %w[HU CO] })["visible"]
    assert_equal ["country_not_enabled"], evaluate({ "countries" => ["CO"] })["reasons"]
    assert evaluate({ "countries" => [] }, country: "ZZ")["visible"]
  end

  def test_pages
    assert_equal ["page_disabled"], evaluate({}, page: "quick_buy")["reasons"]
    assert evaluate({}, page: "cart")["visible"]
    assert evaluate({}, page: "api")["visible"]
    assert evaluate({}, page: nil)["visible"]
  end

  def test_product_scope
    selected = { "products" => { "scope" => "selected", "include_product_ids" => ["8111"], "include_collection_ids" => [] } }
    assert evaluate(selected)["visible"]
    other = { "lines" => [line, line("product_id" => "1", "collection_ids" => [])], "total_cents" => 1 }
    assert_equal ["product_not_included"], evaluate(selected, cart: other)["reasons"]
    by_collection = { "products" => { "scope" => "selected", "include_product_ids" => [], "include_collection_ids" => ["301"] } }
    assert evaluate(by_collection)["visible"]
  end

  def test_exclude_lists_always_apply
    assert_equal ["product_excluded"], evaluate({ "products" => { "scope" => "all", "exclude_product_ids" => ["8111"] } })["reasons"]
    assert_equal ["product_excluded"], evaluate({ "products" => { "scope" => "all", "exclude_collection_ids" => [301] } })["reasons"]
  end

  def test_order_total_range_with_message
    range = { "order_total" => { "min_cents" => 200_000, "max_cents" => nil, "message" => "Minimum order is 2 000 Ft" } }
    result = evaluate(range)
    assert_equal ["order_total_out_of_range"], result["reasons"]
    assert_equal "Minimum order is 2 000 Ft", result["message"]
    assert evaluate({ "order_total" => { "min_cents" => 199_900, "max_cents" => 199_900, "message" => "" } })["visible"]
    assert_nil evaluate({ "order_total" => { "min_cents" => nil, "max_cents" => 100, "message" => "" } })["message"]
  end

  def test_out_of_stock
    cart = { "lines" => [line("available" => false)], "total_cents" => 1 }
    assert_equal ["out_of_stock"], evaluate({}, cart: cart)["reasons"]
    assert evaluate({ "hide_out_of_stock" => false }, cart: cart)["visible"]
  end
end
