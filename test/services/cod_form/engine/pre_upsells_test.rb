# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEnginePreUpsellsTest < Minitest::Test
  include EngineTestHelper
  P = CodForm::Engine::PreUpsells
  Q = CodForm::Engine::Quote

  def item(variant_id, product_id, overrides = {})
    line("variant_id" => variant_id, "product_id" => product_id, "title" => "Shampoo #{product_id}",
         "variant_title" => "200 ml", "unit_price_cents" => 50_000, "compare_at_cents" => nil, "collection_ids" => ["900"]).merge(overrides)
          .reject { |key, _| %w[key quantity properties].include?(key) }
  end

  def catalog
    {
      "61" => item("61", "601"), "62" => item("62", "601", "variant_title" => "500 ml", "unit_price_cents" => 90_000),
      "71" => item("71", "701", "unit_price_cents" => 30_000, "compare_at_cents" => 40_000),
      "81" => item("81", "801", "available" => false),
      "91" => item("91", "8111") # the product already in the cart
    }
  end

  def rule(overrides = {}, config = {})
    {
      "id" => 50, "offer_type" => "pre_upsell", "name" => "Shampoo with oil", "status" => "active", "priority" => 0,
      "targeting" => { "scope" => "selected", "product_ids" => ["8111"], "collection_ids" => [] },
      "config" => {
        "match" => "any", "source" => "products", "max_products" => 3, "discount_type" => "percentage", "value" => 20,
        "title" => { "default" => "Wait! Add these" }, "quantity_picker" => true, "max_quantity" => 3,
        "candidates" => [{ "product_id" => "8111", "variant_ids" => ["91"] }, { "product_id" => "601", "variant_ids" => %w[61 62] },
                         { "product_id" => "801", "variant_ids" => ["81"] }, { "product_id" => "701", "variant_ids" => ["71"] }]
      }.merge(config)
    }.merge(overrides)
  end

  # --- which rule ---------------------------------------------------------------------------------

  def test_cart_condition_any_all_and_scope
    lines = [line]
    assert P.cart_matches?(rule, lines)
    refute P.cart_matches?(rule("targeting" => { "scope" => "selected", "product_ids" => ["999"], "collection_ids" => [] }), lines)
    assert P.cart_matches?(rule("targeting" => { "scope" => "selected", "product_ids" => [], "collection_ids" => ["301"] }), lines)
    assert P.cart_matches?(rule("targeting" => { "scope" => "all" }), lines)
    both = { "scope" => "selected", "product_ids" => %w[8111 8222], "collection_ids" => [] }
    assert P.cart_matches?(rule({ "targeting" => both }, "match" => "any"), lines)
    refute P.cart_matches?(rule({ "targeting" => both }, "match" => "all"), lines)
    assert P.cart_matches?(rule({ "targeting" => both }, "match" => "all"), lines + [line("key" => "l1", "product_id" => "8222")])
  end

  def test_cart_value_range_and_priority
    cheap = rule({ "id" => 51, "priority" => 0 }, "max_cart_cents" => 100_000)
    rich = rule({ "id" => 52, "priority" => 1 }, "min_cart_cents" => 100_000)
    assert_equal 51, P.match(offers: [rich, cheap], lines: [line], merchandise_cents: 50_000, catalog: catalog)["id"]
    assert_equal 52, P.match(offers: [rich, cheap], lines: [line], merchandise_cents: 199_900, catalog: catalog)["id"]
    assert_nil P.match(offers: [rule({}, "min_cart_cents" => 500_000)], lines: [line], merchandise_cents: 199_900, catalog: catalog)
    assert_nil P.match(offers: [rule("status" => "paused")], lines: [line], merchandise_cents: 1, catalog: catalog)
  end

  def test_a_rule_with_nothing_left_to_offer_is_skipped
    empty = rule({ "id" => 53 }, "candidates" => [{ "product_id" => "801", "variant_ids" => ["81"] }])
    assert_equal 50, P.match(offers: [empty, rule("priority" => 5)], lines: [line], merchandise_cents: 1, catalog: catalog)["id"]
  end

  # --- what it offers -----------------------------------------------------------------------------

  def test_products_skip_cart_and_unsellable_and_respect_the_limit
    products = P.products(offer: rule, catalog: catalog, lines: [line])
    assert_equal %w[601 701], products.map { |p| p["product_id"] }
    assert_equal [%w[61 62], ["71"]], products.map { |p| p["variants"].map { |v| v["variant_id"] } }
    assert_equal [40_000, 72_000], products.first["variants"].map { |v| v["offer_price_cents"] }
    assert_equal 50_000, products.first["variants"].first["compare_at_cents"]
    assert_equal 40_000, products.last["variants"].first["compare_at_cents"] # its own compare-at stays
    assert_equal ["601"], P.products(offer: rule({}, "max_products" => 1), catalog: catalog, lines: [line]).map { |p| p["product_id"] }
    stock = catalog.merge("71" => item("71", "701", "inventory_quantity" => 0))
    assert_equal ["601"], P.products(offer: rule, catalog: stock, lines: [line]).map { |p| p["product_id"] }
  end

  def test_offer_prices
    assert_equal 50_000, P.offer_price({ "discount_type" => "none" }, 50_000)
    assert_equal 40_000, P.offer_price({ "discount_type" => "percentage", "value" => 20 }, 50_000)
    assert_equal 0, P.offer_price({ "discount_type" => "percentage", "value" => 150 }, 50_000)
    assert_equal 45_000, P.offer_price({ "discount_type" => "fixed_amount", "value" => 5_000 }, 50_000)
    assert_equal 0, P.offer_price({ "discount_type" => "fixed_amount", "value" => 90_000 }, 50_000)
    assert_equal 29_900, P.offer_price({ "discount_type" => "fixed_price", "value" => 29_900 }, 50_000)
    assert_equal 50_000, P.offer_price({ "discount_type" => "fixed_price", "value" => 90_000 }, 50_000) # never above the price
  end

  def test_resolve_only_offered_variants_of_the_rule
    selected = [
      { "offer_id" => 50, "variant_id" => "62", "quantity" => 9 },
      { "offer_id" => 50, "variant_id" => "61", "quantity" => 1 },  # same product twice: ignored
      { "offer_id" => 50, "variant_id" => "91", "quantity" => 1 },  # already in the cart
      { "offer_id" => 99, "variant_id" => "71", "quantity" => 1 },  # another rule
      { "offer_id" => 50, "variant_id" => "12345", "quantity" => 1 } # not part of the rule
    ]
    lines = P.resolve(offer: rule, selected: selected, catalog: catalog, lines: [line])
    assert_equal 1, lines.length
    pre = lines.first
    assert_equal ["pre_50_62", "pre_upsell", 50, "62", 3, 90_000, 72_000, 18_000, 216_000],
                 pre.values_at("key", "kind", "offer_id", "variant_id", "quantity", "original_unit_price_cents",
                               "unit_price_cents", "unit_discount_cents", "line_total_cents")
    single = P.resolve(offer: rule({}, "quantity_picker" => false), selected: [selected.first], catalog: catalog, lines: [line])
    assert_equal 1, single.first["quantity"]
  end

  # --- in the quote -------------------------------------------------------------------------------

  def test_quote_adds_the_lines_and_names_the_rule
    offers = { "quantity" => [], "bumps" => [], "downsell" => nil, "thresholds" => [], "pre_upsells" => [rule] }
    plain = Q.build(quote_input("offers" => offers, "bump_catalog" => catalog))
    assert_equal({ "offer_id" => 50 }, plain["pre_upsell"])
    assert_empty plain["extra_lines"]

    added = Q.build(quote_input("offers" => offers, "bump_catalog" => catalog,
                                "selected_pre_upsells" => [{ "offer_id" => 50, "variant_id" => "71", "quantity" => 2 }]))
    extra = added["extra_lines"].first
    assert_equal ["pre_upsell", 50, "71", 2, 24_000, 48_000], extra.values_at("kind", "offer_id", "variant_id", "quantity", "unit_price_cents", "line_total_cents")
    assert_equal plain["total_cents"] + 48_000, added["total_cents"]
    assert_equal plain["merchandise_total_cents"] + 48_000, added["merchandise_total_cents"]
    draft = added["_draft"]["lines"].find { |l| l["kind"] == "pre_upsell" }
    assert_equal [30_000, 6_000, "fixed", "Wait! Add these"], draft.values_at("unit_price_cents", "unit_discount_cents", "discount_value_type", "discount_title")

    gone = Q.build(quote_input("offers" => offers, "bump_catalog" => catalog,
                               "selected_pre_upsells" => [{ "offer_id" => 50, "variant_id" => "81", "quantity" => 1 }]))
    assert_includes gone["warnings"], "pre_upsell_unavailable"
    assert_equal plain["total_cents"], gone["total_cents"]

    none = Q.build(quote_input("offers" => offers.merge("pre_upsells" => [rule({}, "min_cart_cents" => 900_000)]), "bump_catalog" => catalog,
                               "selected_pre_upsells" => [{ "offer_id" => 50, "variant_id" => "71", "quantity" => 1 }]))
    assert_nil none["pre_upsell"]
    assert_empty none["extra_lines"]
  end

  def test_draft_order_line_is_marked
    offers = { "quantity" => [], "bumps" => [], "downsell" => nil, "thresholds" => [], "pre_upsells" => [rule] }
    quote = Q.build(quote_input("offers" => offers, "bump_catalog" => catalog,
                                "selected_pre_upsells" => [{ "offer_id" => 50, "variant_id" => "61", "quantity" => 1 }]))
    input = E::DraftOrderBuilder.build(quote: quote, contact: { "first_name" => "Anna" }, address: { "country" => "HU" },
                                       meta: { "country" => "HU" })
    item = input["lineItems"].find { |l| l["variantId"] == "gid://shopify/ProductVariant/61" }
    assert_equal({ "key" => "_codk_line", "value" => "pre_upsell:50" }, item["customAttributes"].last)
    assert_equal "FIXED_AMOUNT", item["appliedDiscount"]["valueType"]
    assert_in_delta 100.0, item["appliedDiscount"]["value"]
  end
end
