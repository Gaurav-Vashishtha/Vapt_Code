# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineBundlesTest < Minitest::Test
  include EngineTestHelper
  B = CodForm::Engine::Bundles
  Q = CodForm::Engine::Quote

  def bundle(config = {}, overrides = {})
    {
      "id" => 70, "offer_type" => "bundle", "name" => "Hair kit", "status" => "active", "priority" => 0,
      "targeting" => { "scope" => "all" },
      "config" => { "product_ids" => %w[1 2 3], "discount_type" => "percentage", "value" => 20,
                    "title" => { "default" => "Hair kit" }, "show_in_form" => true, "show_on_product_page" => true,
                    "candidates" => [{ "product_id" => "1", "variant_ids" => %w[11] }, { "product_id" => "2", "variant_ids" => %w[21 22] },
                                     { "product_id" => "3", "variant_ids" => %w[31] }] }.merge(config)
    }.merge(overrides)
  end

  def item(key, product, variant, price, quantity = 1)
    line("key" => key, "product_id" => product, "variant_id" => variant, "unit_price_cents" => price, "quantity" => quantity,
         "compare_at_cents" => nil)
  end

  def kit(quantities = [1, 1, 1])
    [item("l0", "1", "11", 50_000, quantities[0]), item("l1", "2", "21", 30_000, quantities[1]), item("l2", "3", "31", 20_000, quantities[2])]
  end

  def test_complete_set_gets_the_discount_split_by_price
    lines = B.apply(lines: kit, offers: [bundle])
    assert_equal [10_000, 6_000, 4_000], lines.map { |l| l["unit_discount_cents"] }
    assert_equal ["Hair kit"] * 3, lines.map { |l| l["discount_title"] }
    assert_equal [70] * 3, lines.map { |l| l["bundle_offer_id"] }
  end

  def test_incomplete_set_gets_nothing
    lines = B.apply(lines: kit.first(2), offers: [bundle])
    assert_equal [0, 0], lines.map { |l| l["unit_discount_cents"].to_i }
  end

  def test_extra_units_are_not_discounted_beyond_the_sets
    lines = B.apply(lines: kit([2, 1, 1]), offers: [bundle])
    # one set: the 10 000 share of product 1 is spread over its 2 units
    assert_equal [5_000, 6_000, 4_000], lines.map { |l| l["unit_discount_cents"] }
    two = B.apply(lines: kit([2, 2, 2]), offers: [bundle])
    assert_equal [10_000, 6_000, 4_000], two.map { |l| l["unit_discount_cents"] }
  end

  def test_fixed_amount_and_fixed_price
    off = B.apply(lines: kit, offers: [bundle("discount_type" => "fixed_amount", "value" => 15_000)])
    assert_equal 15_000, off.sum { |l| l["unit_discount_cents"] }
    price = B.apply(lines: kit, offers: [bundle("discount_type" => "fixed_price", "value" => 79_900)])
    assert_equal 100_000 - 79_900, price.sum { |l| l["unit_discount_cents"] }
    none = B.apply(lines: kit, offers: [bundle("discount_type" => "fixed_price", "value" => 200_000)])
    assert_equal 0, none.sum { |l| l["unit_discount_cents"].to_i }
  end

  def test_one_bundle_per_line_by_priority_and_paused_ignored
    second = bundle({ "product_ids" => %w[1 2], "value" => 50 }, "id" => 71, "priority" => 5)
    lines = B.apply(lines: kit, offers: [second, bundle])
    assert_equal [70, 70, 70], lines.map { |l| l["bundle_offer_id"] }
    paused = B.apply(lines: kit, offers: [bundle({}, "status" => "paused")])
    assert_equal 0, paused.sum { |l| l["unit_discount_cents"].to_i }
  end

  def test_public_bundle_needs_every_product_sellable
    catalog = {
      "11" => item("x", "1", "11", 50_000).merge("title" => "Oil"), "21" => item("x", "2", "21", 30_000).merge("title" => "Shampoo"),
      "22" => item("x", "2", "22", 35_000).merge("variant_title" => "Large"), "31" => item("x", "3", "31", 20_000).merge("title" => "Comb")
    }
    pub = B.public_bundle(offer: bundle, catalog: catalog)
    assert_equal %w[1 2 3], pub["products"].map { |p| p["product_id"] }
    assert_equal %w[21 22], pub["products"][1]["variants"].map { |v| v["variant_id"] }
    assert_nil B.public_bundle(offer: bundle, catalog: catalog.merge("31" => catalog["31"].merge("available" => false)))
  end

  def test_quote_lists_the_bundle_discount
    offers = { "quantity" => [], "bumps" => [], "downsell" => nil, "thresholds" => [], "bundles" => [bundle] }
    quote = Q.build(quote_input("lines" => kit, "offers" => offers))
    entry = quote["discounts"].find { |d| d["kind"] == "bundle" }
    assert_equal({ "kind" => "bundle", "title" => "Hair kit", "amount_cents" => 20_000, "offer_id" => 70, "localized" => false }, entry)
    assert_equal 100_000 - 20_000, quote["merchandise_total_cents"]
    assert_nil quote["quantity_offer"]
    draft = quote["_draft"]["lines"].map { |l| [l["unit_discount_cents"], l["discount_value_type"]] }
    assert_equal [[10_000, "fixed"], [6_000, "fixed"], [4_000, "fixed"]], draft
  end
end
