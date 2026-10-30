# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineShippingRatesTest < Minitest::Test
  include EngineTestHelper
  S = CodForm::Engine::ShippingRates

  ADDRESS = { "country" => "HU", "province" => "BU", "zip" => "1051" }.freeze

  def select(rates, cart: nil, address: ADDRESS, subtotal: 199_900, currency: "HUF", selected_id: nil, free: false)
    cart ||= { "lines" => [line] }
    S.select(rates: rates, cart: cart, address: address, subtotal_cents: subtotal, currency: currency,
             selected_id: selected_id, free_shipping: free)
  end

  def test_single_rate_is_preselected
    result = select([shipping_rate])
    assert_equal [{ "id" => 4, "name" => "Standard delivery", "description" => "2-4 business days", "price_cents" => 149_000 }], result["rates"]
    assert_equal 4, result["selected_id"]
    assert_equal 149_000, result["price_cents"]
    refute result["none_available"]
    refute result["pending_address"]
  end

  def test_order_by_position_then_price_and_keeps_valid_selection
    rates = [shipping_rate("id" => 1, "position" => 1, "price_cents" => 100),
             shipping_rate("id" => 2, "position" => 0, "price_cents" => 900),
             shipping_rate("id" => 3, "position" => 0, "price_cents" => 500)]
    result = select(rates)
    assert_equal [3, 2, 1], result["rates"].map { |r| r["id"] }
    assert_equal 3, result["selected_id"]
    kept = select(rates, selected_id: 1)
    assert_equal 1, kept["selected_id"]
    assert_equal 100, kept["price_cents"]
    assert_equal 3, select(rates, selected_id: 99)["selected_id"]
  end

  def test_no_qualifying_rate_means_free_shipping
    result = select([shipping_rate("conditions" => { "countries" => ["CO"] })])
    assert_equal [E::ShippingRates::FREE_RATE], result["rates"]
    assert_equal 0, result["selected_id"]
    assert_equal 0, result["price_cents"]
    refute result["none_available"]
    refute result["pending_address"]
    assert_equal [E::ShippingRates::FREE_RATE], select([])["rates"]
  end

  def test_inactive_and_other_currency_rates_are_skipped
    assert_equal [0], select([shipping_rate("active" => false)])["rates"].map { |rate| rate["id"] }
    assert_equal [0], select([shipping_rate("currency" => "EUR")])["rates"].map { |rate| rate["id"] }
    assert matched?(select([shipping_rate("currency" => nil)]))
  end

  def test_subtotal_bounds_are_inclusive
    rate = shipping_rate("conditions" => { "subtotal_min_cents" => 100_000, "subtotal_max_cents" => 199_900 })
    assert matched?(select([rate], subtotal: 199_900))
    assert matched?(select([rate], subtotal: 100_000))
    refute matched?(select([rate], subtotal: 199_901))
    refute matched?(select([rate], subtotal: 99_999))
  end

  def test_free_shipping_rate_above_threshold
    rates = [shipping_rate("id" => 1, "conditions" => { "subtotal_max_cents" => 1_499_999 }),
             shipping_rate("id" => 2, "name" => "Free delivery", "price_cents" => 0, "conditions" => { "subtotal_min_cents" => 1_500_000 })]
    below = select(rates, subtotal: 1_499_999)
    assert_equal [1, 149_000], [below["selected_id"], below["price_cents"]]
    at = select(rates, subtotal: 1_500_000)
    assert_equal [2, 0], [at["selected_id"], at["price_cents"]]
  end

  def test_free_shipping_flag_zeroes_every_rate
    result = select([shipping_rate, shipping_rate("id" => 5, "price_cents" => 300_000, "position" => 1)], free: true)
    assert_equal [0, 0], result["rates"].map { |r| r["price_cents"] }
    assert_equal 0, result["price_cents"]
  end

  def test_weight_and_quantity_count_only_shippable_lines
    cart = { "lines" => [line("quantity" => 2, "grams" => 600), line("requires_shipping" => false, "quantity" => 5, "grams" => 9000)] }
    weight = shipping_rate("conditions" => { "weight_min_grams" => 1200, "weight_max_grams" => 1200 })
    assert matched?(select([weight], cart: cart))
    refute matched?(select([shipping_rate("conditions" => { "weight_max_grams" => 1199 })], cart: cart))
    assert matched?(select([shipping_rate("conditions" => { "quantity_min" => 2, "quantity_max" => 2 })], cart: cart))
    refute matched?(select([shipping_rate("conditions" => { "quantity_min" => 3 })], cart: cart))
  end

  def test_no_line_requires_shipping
    cart = { "lines" => [line("requires_shipping" => false)] }
    expected = { "rates" => [], "selected_id" => nil, "price_cents" => 0, "none_available" => false, "pending_address" => false }
    assert_equal expected, select([shipping_rate], cart: cart)
  end

  def test_province_condition
    rate = shipping_rate("conditions" => { "countries" => ["HU"], "provinces" => %w[HU-BU HU-PE] })
    assert matched?(select([rate]))
    refute matched?(select([rate], address: { "country" => "HU", "province" => "GS" }))
    assert matched?(select([rate], address: { "country" => "hu", "province" => "hu-pe" }))
  end

  def test_pending_address
    rate = shipping_rate("conditions" => { "countries" => ["HU"], "provinces" => ["HU-BU"] })
    no_address = select([rate], address: {})
    assert no_address["pending_address"]
    assert no_address["none_available"]
    no_province = select([rate], address: { "country" => "HU" })
    assert no_province["pending_address"]
    wrong_country = select([rate], address: { "country" => "CO" })
    refute wrong_country["pending_address"]
    unconditional = select([rate, shipping_rate("id" => 9)], address: {})
    assert_equal 9, unconditional["selected_id"]
    assert unconditional["pending_address"]
  end

  def test_product_conditions
    only = shipping_rate("conditions" => { "products" => { "mode" => "only", "product_ids" => ["8111"], "collection_ids" => [] } })
    exclude = shipping_rate("conditions" => { "products" => { "mode" => "exclude", "product_ids" => [], "collection_ids" => ["301"] } })
    any = shipping_rate("conditions" => { "products" => { "mode" => "any", "product_ids" => ["1"], "collection_ids" => [] } })
    mixed = { "lines" => [line, line("product_id" => "8222", "collection_ids" => [])] }
    assert matched?(select([only]))
    refute matched?(select([only], cart: mixed))
    refute matched?(select([exclude]))
    assert matched?(select([exclude], cart: { "lines" => [line("collection_ids" => ["7"])] }))
    assert matched?(select([any]))
  end

  private

  # A stored rate fits (the free fallback rate, id 0, does not count).
  def matched?(result)
    result["rates"].any? { |rate| rate["id"] != 0 }
  end
end
