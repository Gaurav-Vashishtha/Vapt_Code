# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineOffersTest < Minitest::Test
  include EngineTestHelper
  O = CodForm::Engine::Offers

  def tiers(quantity, offer = quantity_offer, overrides = {})
    O.apply_quantity_tiers(lines: [line({ "quantity" => quantity }.merge(overrides))], offers: [offer]).first
  end

  def offer_with(tiers, higher: true)
    quantity_offer("config" => { "tiers" => tiers, "apply_to_higher_quantities" => higher })
  end

  # --- quantity tiers ---------------------------------------------------------------------------

  def test_tier_boundaries
    one = tiers(1)
    assert_equal [0, 0, 12], [one["unit_discount_cents"], one["tier_index"], one["offer_id"]]
    assert_nil one["discount_title"]
    two = tiers(2)
    assert_equal [19_990, 1, "2 packs"], [two["unit_discount_cents"], two["tier_index"], two["discount_title"]]
    three = tiers(3)
    assert_equal [50_000, 2, "3 packs"], [three["unit_discount_cents"], three["tier_index"], three["discount_title"]]
    assert_equal 50_000, tiers(7)["unit_discount_cents"] # largest tier quantity <= n
  end

  def test_exact_match_only_when_higher_quantities_are_off
    offer = offer_with([{ "quantity" => 2, "discount_type" => "percentage", "value" => 10, "label" => { "default" => "2" } },
                        { "quantity" => 4, "discount_type" => "percentage", "value" => 20, "label" => { "default" => "4" } }], higher: false)
    assert_equal 19_990, tiers(2, offer)["unit_discount_cents"]
    assert_equal 0, tiers(3, offer)["unit_discount_cents"]
    assert_nil tiers(3, offer)["tier_index"]
    assert_equal 39_980, tiers(4, offer)["unit_discount_cents"]
    assert_equal 0, tiers(5, offer)["unit_discount_cents"]
    assert_equal 0, tiers(1, offer)["unit_discount_cents"]
  end

  def test_below_the_first_tier_gets_nothing
    offer = offer_with([{ "quantity" => 3, "discount_type" => "percentage", "value" => 10, "label" => { "default" => "3" } }])
    assert_nil tiers(2, offer)["tier_index"]
    assert_equal 19_990, tiers(3, offer)["unit_discount_cents"]
  end

  def test_tiers_are_sorted_by_quantity
    offer = offer_with([{ "quantity" => 3, "discount_type" => "percentage", "value" => 20, "label" => { "default" => "3" } },
                        { "quantity" => 2, "discount_type" => "percentage", "value" => 10, "label" => { "default" => "2" } }])
    assert_equal [1, "3"], [tiers(3, offer)["tier_index"], tiers(3, offer)["discount_title"]]
    assert_equal 0, tiers(2, offer)["tier_index"]
  end

  def test_percentage_rounding_per_unit
    offer = offer_with([{ "quantity" => 1, "discount_type" => "percentage", "value" => 15, "label" => { "default" => "x" } }])
    discounted = tiers(3, offer, "unit_price_cents" => 999)
    assert_equal 150, discounted["unit_discount_cents"] # 149.85 -> 150 per unit, 450 for the line
    assert_equal "percentage", discounted["discount_value_type"]
  end

  def test_fixed_amount_is_split_per_unit_with_integer_division
    offer = offer_with([{ "quantity" => 3, "discount_type" => "fixed_amount", "value" => 100_000, "label" => { "default" => "x" } }])
    assert_equal 33_333, tiers(3, offer)["unit_discount_cents"]   # charged 99 999, never more than the value
    assert_equal 25_000, tiers(4, offer)["unit_discount_cents"]
    assert_equal "fixed", tiers(3, offer)["discount_value_type"]
  end

  def test_unit_price_tier_never_raises_the_price
    offer = offer_with([{ "quantity" => 1, "discount_type" => "unit_price", "value" => 250_000, "label" => { "default" => "x" } }])
    assert_equal 0, tiers(1, offer)["unit_discount_cents"]
  end

  def test_discount_is_capped_at_the_unit_price
    offer = offer_with([{ "quantity" => 1, "discount_type" => "fixed_amount", "value" => 999_999, "label" => { "default" => "x" } }])
    assert_equal 199_900, tiers(1, offer)["unit_discount_cents"]
  end

  def test_targeting_priority_and_status
    by_collection = quantity_offer("id" => 13, "targeting" => { "scope" => "selected", "product_ids" => [], "collection_ids" => ["301"] })
    all = quantity_offer("id" => 14, "priority" => 5, "targeting" => { "scope" => "all" })
    paused = quantity_offer("id" => 15, "priority" => -1, "status" => "paused")
    assert_equal 13, O.match_quantity_offer(offers: [all, by_collection, paused], line: line)["id"]
    assert_equal 14, O.match_quantity_offer(offers: [all, by_collection], line: line("product_id" => "1", "collection_ids" => []))["id"]
    assert_nil O.match_quantity_offer(offers: [quantity_offer], line: line("product_id" => "1"))
    assert_nil O.match_quantity_offer(offers: [paused], line: line)
  end

  def test_bundle_app_lines_never_get_a_tier
    bundled = tiers(3, quantity_offer, "properties" => { "_bundle_id" => "abc" })
    assert_equal 0, bundled["unit_discount_cents"]
    assert_nil bundled["offer_id"]
    assert_equal 50_000, tiers(3, quantity_offer, "properties" => { "Engraving" => "Anna" })["unit_discount_cents"]
  end

  # --- downsell ---------------------------------------------------------------------------------

  def test_downsell_percentage_applies_after_the_quantity_offer
    lines = O.apply_quantity_tiers(lines: [line("quantity" => 2)], offers: [quantity_offer])
    downsell = { "id" => 30, "config" => { "discount_type" => "percentage", "value" => 10, "title" => { "default" => "Wait!" } } }
    result = O.apply_downsell(lines: lines, offer: downsell).first
    assert_equal 17_991, result["downsell_unit_discount_cents"] # 10% of 179 910
    assert_equal 37_981, result["unit_discount_cents"]
    assert_equal "2 packs + Wait!", result["discount_title"]
    assert_equal "fixed", result["discount_value_type"]
    assert_equal 19_990, lines.first["unit_discount_cents"], "input lines are not mutated"
  end

  def test_downsell_fixed_amount_is_proportional_and_never_exceeds_the_value
    lines = [line("key" => "a", "quantity" => 1, "unit_price_cents" => 30_000), line("key" => "b", "quantity" => 3, "unit_price_cents" => 10_000)]
    downsell = { "id" => 30, "config" => { "discount_type" => "fixed_amount", "value" => 10_000, "title" => { "default" => "Wait!" } } }
    result = O.apply_downsell(lines: lines, offer: downsell)
    charged = result.sum { |l| l["unit_discount_cents"] * l["quantity"] }
    # 5000 / 5000 by line total; 5000 / 3 = 1666 per unit leaves 2 cents, handed to the single-unit line
    assert_equal [5002, 1666], result.map { |l| l["unit_discount_cents"] }
    assert_equal 10_000, charged
    odd = O.apply_downsell(lines: [line("quantity" => 3, "unit_price_cents" => 10_000)], offer: downsell)
    assert_equal 3333, odd.first["unit_discount_cents"], "9 999 charged, never more than the value"
    exact = O.apply_downsell(lines: [line("quantity" => 2)], offer: downsell)
    assert_equal 5000, exact.first["unit_discount_cents"]
  end

  def test_downsell_fixed_amount_is_capped_at_the_merchandise
    downsell = { "id" => 30, "config" => { "discount_type" => "fixed_amount", "value" => 999_999, "title" => { "default" => "W" } } }
    result = O.apply_downsell(lines: [line("unit_price_cents" => 5000, "quantity" => 2)], offer: downsell)
    assert_equal 5000, result.first["unit_discount_cents"]
  end

  def test_downsell_without_offer_changes_nothing
    lines = [line]
    assert_equal lines, O.apply_downsell(lines: lines, offer: nil)
  end

  # --- discount codes ---------------------------------------------------------------------------

  def code(overrides = {})
    { "code" => "WELCOME10", "kind" => "percentage", "value" => 10, "applies_to" => { "all" => true },
      "min_subtotal_cents" => nil, "min_quantity" => nil }.merge(overrides)
  end

  def apply_code(code, lines: nil, combine: false, subtotal: nil, quantity: nil)
    lines ||= [line("quantity" => 2, "unit_discount_cents" => 0)]
    subtotal ||= lines.sum { |l| (l["unit_price_cents"] - l["unit_discount_cents"].to_i) * l["quantity"] }
    quantity ||= lines.sum { |l| l["quantity"] }
    O.apply_discount_code(lines: lines, code: code, subtotal_cents: subtotal, quantity: quantity,
                          stacking: { "codes_combine_with_offers" => combine })
  end

  def test_percentage_code
    assert_equal({ "status" => "applied", "amount_cents" => 39_980, "free_shipping" => false }, apply_code(code))
  end

  def test_fixed_code_is_capped_at_the_eligible_total
    assert_equal 50_000, apply_code(code("kind" => "fixed_amount", "value" => 50_000))["amount_cents"]
    assert_equal 399_800, apply_code(code("kind" => "fixed_amount", "value" => 9_999_999))["amount_cents"]
  end

  def test_stacking_toggle
    discounted = O.apply_quantity_tiers(lines: [line("quantity" => 2)], offers: [quantity_offer])
    refused = apply_code(code, lines: discounted, combine: false)
    assert_equal({ "status" => "not_combinable", "amount_cents" => 0, "free_shipping" => false }, refused)
    combined = apply_code(code, lines: discounted, combine: true)
    assert_equal "applied", combined["status"]
    assert_equal 35_982, combined["amount_cents"] # 10% of what remains: 359 820
    no_offer = apply_code(code, lines: O.apply_quantity_tiers(lines: [line("quantity" => 1)], offers: [quantity_offer]), combine: false)
    assert_equal "applied", no_offer["status"], "a tier without a discount does not block the code"
  end

  def test_minimums
    assert_equal "minimum_not_met", apply_code(code("min_subtotal_cents" => 399_801))["status"]
    assert_equal "applied", apply_code(code("min_subtotal_cents" => 399_800))["status"]
    assert_equal "minimum_not_met", apply_code(code("min_quantity" => 3))["status"]
    assert_equal "applied", apply_code(code("min_quantity" => 2))["status"]
  end

  def test_applies_to_products_and_collections
    lines = [line("quantity" => 1, "unit_discount_cents" => 0), line("product_id" => "8222", "collection_ids" => ["77"], "unit_price_cents" => 10_000, "quantity" => 1, "unit_discount_cents" => 0)]
    assert_equal 1000, apply_code(code("applies_to" => { "product_ids" => ["8222"], "collection_ids" => [] }), lines: lines)["amount_cents"]
    assert_equal 1000, apply_code(code("applies_to" => { "product_ids" => [], "collection_ids" => ["77"] }), lines: lines)["amount_cents"]
    assert_equal "not_applicable", apply_code(code("applies_to" => { "product_ids" => ["1"], "collection_ids" => [] }), lines: lines)["status"]
  end

  def test_free_shipping_code_and_unusable_codes
    assert_equal({ "status" => "applied", "amount_cents" => 0, "free_shipping" => true }, apply_code(code("kind" => "free_shipping", "value" => 0)))
    assert_equal "not_applicable", apply_code(nil)["status"]
    assert_equal "not_applicable", apply_code({ "code" => "X", "error" => "not_found" })["status"]
    assert_equal "not_applicable", apply_code(code("kind" => "bxgy"))["status"]
  end

  # --- bumps ------------------------------------------------------------------------------------

  def bump(overrides = {}, config = {})
    { "id" => 21, "offer_type" => "bump", "name" => "Express", "status" => "active", "priority" => 0, "targeting" => { "scope" => "all" },
      "config" => { "title" => { "default" => "Express handling" }, "kind" => "custom", "variant_id" => nil, "price_cents" => 49_900,
                    "quantity_picker" => false, "max_quantity" => 1, "requires_shipping" => false, "taxable" => true }.merge(config) }.merge(overrides)
  end

  def test_custom_bump
    lines = O.resolve_bumps(offers: [bump], selected: [{ "offer_id" => 21, "quantity" => 5 }], cart: { "lines" => [line] }, catalog: {})
    assert_equal 1, lines.length
    first = lines.first
    assert_equal ["bump_21", "bump", "custom", 1, 49_900, 49_900], first.values_at("key", "kind", "bump_kind", "quantity", "unit_price_cents", "line_total_cents")
    refute first["requires_shipping"]
  end

  def test_bump_quantity_picker_is_clamped
    offer = bump({}, "quantity_picker" => true, "max_quantity" => 3)
    pick = ->(q) { O.resolve_bumps(offers: [offer], selected: [{ "offer_id" => 21, "quantity" => q }], cart: { "lines" => [line] }, catalog: {}).first["quantity"] }
    assert_equal [1, 2, 3, 3], [pick.call(0), pick.call(2), pick.call(3), pick.call(9)]
  end

  def test_variant_bump_uses_catalog_price_or_a_lower_configured_price
    catalog = { "44999" => line("variant_id" => "44999", "product_id" => "8999", "unit_price_cents" => 60_000, "title" => "Case") }
    plain = O.resolve_bumps(offers: [bump({}, "kind" => "variant", "variant_id" => "44999", "price_cents" => nil)],
                            selected: [{ "offer_id" => 21, "quantity" => 1 }], cart: { "lines" => [line] }, catalog: catalog).first
    assert_equal [60_000, 0, 60_000], plain.values_at("unit_price_cents", "unit_discount_cents", "original_unit_price_cents")
    cheaper = O.resolve_bumps(offers: [bump({}, "kind" => "variant", "variant_id" => "44999", "price_cents" => 49_900)],
                              selected: [{ "offer_id" => 21, "quantity" => 1 }], cart: { "lines" => [line] }, catalog: catalog).first
    assert_equal [49_900, 10_100, 60_000], cheaper.values_at("unit_price_cents", "unit_discount_cents", "original_unit_price_cents")
    missing = O.resolve_bumps(offers: [bump({}, "kind" => "variant", "variant_id" => "1")],
                              selected: [{ "offer_id" => 21, "quantity" => 1 }], cart: { "lines" => [line] }, catalog: catalog)
    assert_equal [], missing
  end

  def test_only_targeted_selected_and_first_three_bumps_count
    targeted = bump({ "id" => 22, "targeting" => { "scope" => "selected", "product_ids" => ["1"], "collection_ids" => [] } })
    assert_equal [], O.resolve_bumps(offers: [targeted], selected: [{ "offer_id" => 22, "quantity" => 1 }], cart: { "lines" => [line] }, catalog: {})
    assert_equal [], O.resolve_bumps(offers: [bump], selected: [], cart: { "lines" => [line] }, catalog: {})
    four = (1..4).map { |i| bump("id" => i, "priority" => i) }
    picked = O.resolve_bumps(offers: four, selected: four.map { |o| { "offer_id" => o["id"], "quantity" => 1 } }, cart: { "lines" => [line] }, catalog: {})
    assert_equal [1, 2, 3], picked.map { |l| l["offer_id"] }
  end

  # --- thresholds -------------------------------------------------------------------------------

  def test_thresholds
    offers = [{ "id" => 40, "offer_type" => "threshold", "status" => "active", "priority" => 0,
                "config" => { "kind" => "free_shipping", "threshold_cents" => 1_500_000 } }]
    below = O.evaluate_thresholds(offers: offers, merchandise_total_cents: 1_499_999).first
    assert_equal({ "offer_id" => 40, "kind" => "free_shipping", "threshold_cents" => 1_500_000, "remaining_cents" => 1, "reached" => false }, below)
    at = O.evaluate_thresholds(offers: offers, merchandise_total_cents: 1_500_000).first
    assert_equal [0, true], at.values_at("remaining_cents", "reached")
    assert O.evaluate_thresholds(offers: offers, merchandise_total_cents: 2_000_000).first["reached"]
    assert_equal [], O.evaluate_thresholds(offers: [], merchandise_total_cents: 5)
  end

  # --- overlap ----------------------------------------------------------------------------------

  def test_offer_overlap
    a = quantity_offer("id" => 1, "targeting" => { "scope" => "selected", "product_ids" => %w[8111 8112] })
    b = quantity_offer("id" => 2, "targeting" => { "scope" => "selected", "product_ids" => %w[8112 8113] })
    c = quantity_offer("id" => 3, "status" => "paused", "targeting" => { "scope" => "selected", "product_ids" => ["8111"] })
    assert_equal [{ "product_id" => "8112", "offer_ids" => [1, 2] }], E::OfferOverlap.conflicts([a, b, c])
    assert_equal [], E::OfferOverlap.conflicts([a, c])
    all = quantity_offer("id" => 4, "targeting" => { "scope" => "all" })
    assert_equal [{ "product_id" => "*", "offer_ids" => [1, 4] }], E::OfferOverlap.conflicts([a, all])
    assert_equal [], E::OfferOverlap.conflicts([all])
  end
end
