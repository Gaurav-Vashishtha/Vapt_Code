# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineQuoteTest < Minitest::Test
  include EngineTestHelper
  Q = CodForm::Engine::Quote

  HUF = { "template" => "Ft{{amount}}", "decimals" => 0, "thousands" => " ", "decimal" => "," }.freeze
  FEE = { "enabled" => true, "mode" => "fixed", "value" => 500.0, "label" => "Cash on delivery fee", "taxable" => false, "fx_rate" => 1.0 }.freeze

  def build(overrides = {})
    Q.build(quote_input(overrides))
  end

  def offers(overrides = {})
    { "quantity" => [], "bumps" => [], "downsell" => nil, "thresholds" => [] }.merge(overrides)
  end

  def combine(general = E::Defaults.general)
    general.merge("discounts" => { "code_field_enabled" => true, "codes_combine_with_offers" => true })
  end

  def assert_totals_add_up(quote)
    lines_total = quote["lines"].sum { |l| l["line_total_cents"] }
    extras = quote["extra_lines"].sum { |l| l["line_total_cents"] }
    code = quote["discounts"].select { |d| d["kind"] == "discount_code" }.sum { |d| d["amount_cents"] }
    assert_equal quote["merchandise_total_cents"], lines_total + extras - code
    assert_equal quote["subtotal_cents"] - quote["discount_total_cents"] + extras, quote["merchandise_total_cents"]
    tax = quote["tax"]["status"] == "calculated" ? quote["tax"]["amount_cents"] : 0
    assert_equal quote["total_cents"], quote["merchandise_total_cents"] + quote["shipping_cents"] + quote["cod_fee"]["amount_cents"] + tax
    assert_equal quote["discount_total_cents"], quote["discounts"].sum { |d| d["amount_cents"] }
  end

  def test_fixture_cases
    data = fixture("quote_cases")
    data["cases"].each do |c|
      quote = Q.build(data["base_input"].merge(c["input"]))
      c["expected"].each { |key, value| assert_equal value, quote[key], "#{c['name']}: #{key}" }
      assert_equal c["expected_fee_cents"], quote["cod_fee"]["amount_cents"], c["name"] if c.key?("expected_fee_cents")
      assert_equal c["expected_code_status"], quote["discount_code"]["status"], c["name"] if c.key?("expected_code_status")
      assert_totals_add_up(quote)
    end
  end

  def test_automatic_discount_on_lines_and_order
    plain = build
    line = plain["lines"].first
    odd = line["quantity"] > 1 ? 1 : 0 # an amount that does not divide by the quantity
    on_line = line["quantity"] * 10_000 + odd
    quote = build("automatic_discount" => { "amount_cents" => on_line + 500, "title" => "Buy1Get1",
                                            "lines" => { line["key"] => on_line }, "order_cents" => 500 })
    assert_equal line["line_total_cents"] - on_line, quote["lines"].first["line_total_cents"]
    assert_equal line["discount_cents"] + on_line, quote["lines"].first["discount_cents"]
    assert_equal plain["subtotal_cents"], quote["subtotal_cents"]
    assert_equal plain["merchandise_total_cents"] - on_line - 500, quote["merchandise_total_cents"]
    assert_equal plain["discount_total_cents"] + on_line + 500, quote["discount_total_cents"]
    assert_includes quote["discounts"], { "kind" => "automatic", "title" => "Buy1Get1", "amount_cents" => on_line + 500 }
    assert_equal quote["discount_total_cents"], quote["discounts"].sum { |d| d["amount_cents"] }
    assert_equal quote["merchandise_total_cents"] + quote["shipping_cents"] + quote["cod_fee"]["amount_cents"], quote["total_cents"]
    refute_equal plain["_fingerprint"], quote["_fingerprint"]

    # the draft order carries it as explicit discounts and Shopify adds nothing itself
    input = E::DraftOrderBuilder.build(quote: quote, contact: {}, address: {}, meta: {})
    assert_equal false, input["acceptAutomaticDiscounts"]
    item = input["lineItems"].first
    assert_equal "FIXED_AMOUNT", item["appliedDiscount"]["valueType"]
    assert_includes item["appliedDiscount"]["title"], "Buy1Get1"
    per_unit = (item["appliedDiscount"]["value"] * 100).round
    order = (input["appliedDiscount"]["value"] * 100).round
    assert_equal 500 + odd, order, "cents that do not divide by the quantity go to the order discount"
    assert_equal line["discount_cents"] + on_line + 500, per_unit * line["quantity"] + order

    # never more than the line / the merchandise, never negative
    huge = build("automatic_discount" => { "lines" => { line["key"] => 10**9 }, "order_cents" => 10**9 })
    assert_equal 0, huge["lines"].first["line_total_cents"]
    assert_equal 0, huge["merchandise_total_cents"]
    assert_equal plain["total_cents"], build("automatic_discount" => { "lines" => { line["key"] => -5 }, "order_cents" => -5 })["total_cents"]
    # an amount for a line that is not a product line (bump, gift) counts at order level
    other = build("automatic_discount" => { "lines" => { "bump_9" => 700 }, "order_cents" => 0 })
    assert_equal plain["merchandise_total_cents"] - 700, other["merchandise_total_cents"]
  end

  def test_output_shape
    quote = build
    expected = %w[currency lines extra_lines quantity_offer discounts discount_code shipping cod_fee tax subtotal_cents discount_total_cents
                  merchandise_total_cents shipping_cents total_cents savings_cents eligibility payment_options otp_required thresholds warnings
                  pre_upsell local _draft _fingerprint]
    assert_equal expected, quote.keys
    assert_equal %w[key variant_id product_id title variant_title image quantity unit_price_cents compare_at_cents line_subtotal_cents
                    discount_cents discount_title line_total_cents kind available max_quantity], quote["lines"].first.keys
    assert_equal({ "status" => "included", "required" => false, "amount_cents" => 0, "lines" => [] }, quote["tax"])
    assert_equal({ "cod_allowed" => true, "reasons" => [], "message_key" => nil, "message" => nil, "pay_online" => true, "pending" => [] }, quote["eligibility"])
    assert_nil quote["payment_options"]
    assert_nil quote["quantity_offer"]
    assert_nil quote["discount_code"]
    assert_equal false, quote["otp_required"]
    assert JSON.generate(quote), "plain JSON-able hash"
  end

  def test_discount_rows_say_whether_the_title_is_in_the_buyers_language
    own = quantity_offer
    own["config"]["tiers"][1]["label"] = { "default" => "2 packs", "hi" => "दो पैक" }
    hindi = build("lines" => [line("quantity" => 2)], "offers" => offers("quantity" => [own]), "locale" => "hi")
    assert_equal ["दो पैक", true], hindi["discounts"].first.values_at("title", "localized")
    plain = build("lines" => [line("quantity" => 2)], "offers" => offers("quantity" => [quantity_offer]), "locale" => "hi-IN")
    assert_equal ["2 packs", false], plain["discounts"].first.values_at("title", "localized")
  end

  def test_architecture_example_line_and_discount_details
    quote = Q.build(fixture("quote_cases")["base_input"].merge(fixture("quote_cases")["cases"][2]["input"]))
    line = quote["lines"].first
    assert_equal [3, 599_700, 150_000, "3 packs", 449_700, 10], line.values_at("quantity", "line_subtotal_cents", "discount_cents", "discount_title", "line_total_cents", "max_quantity")
    assert_equal({ "offer_id" => 12, "applied_tier_index" => 2, "savings_cents" => 150_000 }, quote["quantity_offer"])
    assert_equal [{ "kind" => "quantity_offer", "title" => "3 packs", "amount_cents" => 150_000, "offer_id" => 12, "localized" => false },
                  { "kind" => "discount_code", "title" => "WELCOME10", "amount_cents" => 49_960, "code" => "WELCOME10" }], quote["discounts"]
    assert_equal({ "code" => "WELCOME10", "status" => "applied", "message_key" => nil }, quote["discount_code"])
    assert_equal ["bump_21", "bump", 21, "Express handling", 1, 49_900, 49_900],
                 quote["extra_lines"].first.values_at("key", "kind", "offer_id", "title", "quantity", "unit_price_cents", "line_total_cents")
    assert_equal [4, 149_000, true, nil], quote["shipping"].values_at("selected_id", "price_cents", "hide_selector", "message")
  end

  def test_session_quote_without_an_address
    rated = shipping_rate("conditions" => { "countries" => ["HU"] })
    quote = build("stage" => "page", "address" => {}, "contact" => {}, "shipping_rates" => [rated],
                  "rules" => { "allow_zips" => "1000-1999" }, "general" => E::Defaults.general.merge("countries" => ["HU"]))
    assert quote["eligibility"]["cod_allowed"]
    assert_equal ["zip"], quote["eligibility"]["pending"]
    assert_equal [true, true, "shipping_enter_address", 0], quote["shipping"].values_at("none_available", "pending_address", "message_key", "price_cents")
    assert_equal 199_900, quote["total_cents"]
    assert_totals_add_up(quote)
  end

  def test_no_qualifying_shipping_rate_ships_free
    quote = build("shipping_rates" => [shipping_rate("conditions" => { "countries" => ["CO"] })])
    assert_equal [false, false, nil, 0], quote["shipping"].values_at("none_available", "pending_address", "message_key", "selected_id")
    assert_equal 0, quote["shipping_cents"]
    assert_equal({ "rate_id" => 0, "title" => "Free shipping", "price_cents" => 0 }, quote["_draft"]["shipping"])
    assert_totals_add_up(quote)
  end

  def test_shipping_is_reevaluated_on_the_discounted_subtotal
    rates = [shipping_rate("id" => 1, "conditions" => { "subtotal_max_cents" => 359_999 }),
             shipping_rate("id" => 2, "name" => "Free", "price_cents" => 0, "conditions" => { "subtotal_min_cents" => 360_000 })]
    without_offer = build("lines" => [line("quantity" => 2)], "shipping_rates" => rates)
    assert_equal [2, 0], without_offer["shipping"].values_at("selected_id", "price_cents")
    with_offer = build("lines" => [line("quantity" => 2)], "shipping_rates" => rates, "offers" => offers("quantity" => [quantity_offer]))
    assert_equal [1, 149_000], with_offer["shipping"].values_at("selected_id", "price_cents") # 359 820 after the 10% tier
  end

  def test_selected_rate_is_kept_and_selector_shown_for_several_rates
    rates = [shipping_rate, shipping_rate("id" => 5, "name" => "Express", "price_cents" => 299_000, "position" => 1)]
    quote = build("shipping_rates" => rates, "selected_shipping_rate_id" => 5)
    assert_equal [5, 299_000, false], quote["shipping"].values_at("selected_id", "price_cents", "hide_selector")
    assert_equal 498_900, quote["total_cents"]
    assert_equal "Express", quote["_draft"]["shipping"]["title"]
  end

  def test_free_shipping_threshold_offer
    threshold = { "id" => 40, "offer_type" => "threshold", "status" => "active", "priority" => 0, "config" => { "kind" => "free_shipping", "threshold_cents" => 399_800 } }
    below = build("offers" => offers("thresholds" => [threshold]))
    assert_equal [{ "offer_id" => 40, "kind" => "free_shipping", "threshold_cents" => 399_800, "remaining_cents" => 199_900, "reached" => false }], below["thresholds"]
    assert_equal 149_000, below["shipping_cents"]
    reached = build("lines" => [line("quantity" => 2)], "offers" => offers("thresholds" => [threshold]))
    assert reached["thresholds"].first["reached"]
    assert_equal [0, 399_800], reached.values_at("shipping_cents", "total_cents")
    assert_equal 0, reached["shipping"]["rates"].first["price_cents"]
  end

  def test_free_gift_threshold_adds_a_zero_priced_line
    threshold = { "id" => 41, "offer_type" => "threshold", "status" => "active", "priority" => 0,
                  "config" => { "kind" => "free_gift", "threshold_cents" => 100_000, "gift_variant_id" => "44777" } }
    catalog = { "44777" => line("variant_id" => "44777", "product_id" => "8777", "title" => "Sticker", "unit_price_cents" => 9900) }
    quote = build("offers" => offers("thresholds" => [threshold]), "bump_catalog" => catalog)
    gift = quote["extra_lines"].first
    assert_equal ["gift_41", "gift", "Sticker", 0, 0], gift.values_at("key", "kind", "title", "unit_price_cents", "line_total_cents")
    assert_equal 348_900, quote["total_cents"]
    missing = build("offers" => offers("thresholds" => [threshold]))
    assert_equal [], missing["extra_lines"]
    assert_includes missing["warnings"], "gift_unavailable"
    assert_nil missing["thresholds"].first["gift"]
  end

  def test_free_gift_threshold_previews_the_gift_before_it_is_reached
    threshold = { "id" => 41, "offer_type" => "threshold", "status" => "active", "priority" => 0,
                  "config" => { "kind" => "free_gift", "threshold_cents" => 900_000, "gift_variant_id" => "44777" } }
    catalog = { "44777" => line("variant_id" => "44777", "product_id" => "8777", "title" => "Sticker", "unit_price_cents" => 9900) }
    quote = build("offers" => offers("thresholds" => [threshold]), "bump_catalog" => catalog)
    entry = quote["thresholds"].first
    assert_equal false, entry["reached"]
    assert_equal({ "title" => "Sticker", "image" => catalog["44777"]["image"], "value_cents" => 9900 }, entry["gift"])
    assert_equal [], quote["extra_lines"]
  end

  def test_free_shipping_discount_code
    code = { "code" => "SHIPFREE", "kind" => "free_shipping", "value" => 0, "applies_to" => { "all" => true } }
    quote = build("discount_code" => code)
    assert_equal ["applied", 0, 199_900], [quote["discount_code"]["status"], quote["shipping_cents"], quote["total_cents"]]
    assert_equal [], quote["discounts"]
  end

  def test_unknown_discount_code_and_minimum
    invalid = build("discount_code" => { "code" => "NOPE", "error" => "not_found" })
    assert_equal({ "code" => "NOPE", "status" => "invalid", "message_key" => "error_discount_invalid", "error" => "not_found" }, invalid["discount_code"])
    assert_equal 348_900, invalid["total_cents"]
    minimum = build("discount_code" => { "code" => "BIG", "kind" => "percentage", "value" => 10, "applies_to" => { "all" => true }, "min_subtotal_cents" => 500_000 })
    assert_equal %w[minimum_not_met error_discount_minimum], minimum["discount_code"].values_at("status", "message_key")
    refused = Q.build(fixture("quote_cases")["base_input"].merge(fixture("quote_cases")["cases"][4]["input"]))
    assert_equal "error_discount_not_combinable", refused["discount_code"]["message_key"]
  end

  def test_downsell_applies_only_when_accepted
    downsell = { "id" => 30, "offer_type" => "downsell", "status" => "active", "config" => { "discount_type" => "percentage", "value" => 10, "title" => { "default" => "Wait!" } } }
    input = { "lines" => [line("quantity" => 2)], "offers" => offers("quantity" => [quantity_offer], "downsell" => downsell) }
    shown = build(input)
    assert_equal 39_980, shown["discount_total_cents"]
    wrong = build(input.merge("downsell_offer_id" => 99))
    assert_equal 39_980, wrong["discount_total_cents"]
    accepted = build(input.merge("downsell_offer_id" => 30))
    assert_equal 75_962, accepted["discount_total_cents"] # 2 x (19 990 + 17 991)
    assert_equal [{ "kind" => "quantity_offer", "title" => "2 packs", "amount_cents" => 39_980, "offer_id" => 12, "localized" => false },
                  { "kind" => "downsell", "title" => "Wait!", "amount_cents" => 35_982, "offer_id" => 30, "localized" => false }], accepted["discounts"]
    assert_equal 39_980, accepted["quantity_offer"]["savings_cents"]
    assert_equal "2 packs + Wait!", accepted["lines"].first["discount_title"]
    assert_totals_add_up(accepted)
  end

  def test_stacking_order_offer_then_downsell_then_code
    downsell = { "id" => 30, "config" => { "discount_type" => "percentage", "value" => 10, "title" => { "default" => "Wait!" } } }
    code = { "code" => "WELCOME10", "kind" => "percentage", "value" => 10, "applies_to" => { "all" => true } }
    quote = build("lines" => [line("quantity" => 2)], "general" => combine, "downsell_offer_id" => 30, "discount_code" => code,
                  "offers" => offers("quantity" => [quantity_offer], "downsell" => downsell))
    assert_equal 32_384, quote["discounts"].last["amount_cents"] # 10% of 399 800 - 75 962 = 323 838
    assert_equal 291_454, quote["merchandise_total_cents"]
    assert_totals_add_up(quote)
  end

  def test_percentage_fee_uses_discounted_merchandise_plus_shipping
    fee = FEE.merge("mode" => "percentage", "value" => 2)
    quote = build("lines" => [line("quantity" => 2)], "offers" => offers("quantity" => [quantity_offer]), "cod_fee" => fee)
    assert_equal 10_200, quote["cod_fee"]["amount_cents"] # 2% of 359 820 + 149 000 = 10 176.4 -> 10 200
    assert_equal 519_020, quote["total_cents"]
    assert_equal({ "label" => "Cash on delivery fee", "amount_cents" => 10_200, "taxable" => false }, quote["_draft"]["cod_fee"])
  end

  def test_tax_states
    excluded = build("tax" => { "prices_include_tax" => false, "calculated" => nil })
    assert_equal({ "status" => "none", "required" => true, "amount_cents" => 0, "lines" => [] }, excluded["tax"])
    assert_equal 348_900, excluded["total_cents"]
    calculated = build("tax" => { "prices_include_tax" => false, "calculated" => { "amount_cents" => 53_973, "lines" => [{ "title" => "VAT", "rate" => 0.27 }] } })
    assert_equal ["calculated", true, 53_973], calculated["tax"].values_at("status", "required", "amount_cents")
    assert_equal 402_873, calculated["total_cents"]
    assert_totals_add_up(calculated)
    unavailable = build("tax" => { "prices_include_tax" => false, "calculated" => nil, "unavailable" => true })
    assert_equal "unavailable", unavailable["tax"]["status"]
    included = build("tax" => { "prices_include_tax" => true, "calculated" => { "amount_cents" => 53_973 } })
    assert_equal ["included", 348_900], [included["tax"]["status"], included["total_cents"]]
  end

  def test_cod_rules_remove_cod
    quote = build("rules" => { "deny_zips" => "10*" })
    assert_equal [false, ["zip_not_allowed"], "error_not_eligible", true], quote["eligibility"].values_at("cod_allowed", "reasons", "message_key", "pay_online")
    assert_nil quote["payment_options"]
    total_rule = build("lines" => [line("quantity" => 2)], "offers" => offers("quantity" => [quantity_offer]), "rules" => { "max_total_cents" => 359_820 })
    assert total_rule["eligibility"]["cod_allowed"], "rule total is the merchandise total after discounts"
    refute build("lines" => [line("quantity" => 2)], "rules" => { "max_total_cents" => 359_820 })["eligibility"]["cod_allowed"]
  end

  def test_visibility_rules_apply
    country = build("general" => E::Defaults.general.merge("countries" => ["CO"]))
    assert_equal ["country_not_enabled"], country["eligibility"]["reasons"]
    range = build("general" => E::Defaults.general.merge("order_total" => { "min_cents" => 500_000, "max_cents" => nil, "message" => "Minimum 5 000 Ft" }))
    assert_equal [["order_total_out_of_range"], "Minimum 5 000 Ft"], range["eligibility"].values_at("reasons", "message")
  end

  def test_block_result_from_the_adapter
    blocked = build("block" => { "blocked" => true, "reason" => "phone_blocked" }, "fraud" => E::Defaults.fraud.merge("blocked_message" => "No COD for you."))
    assert_equal [false, ["phone_blocked"], "error_blocked", "No COD for you."], blocked["eligibility"].values_at("cod_allowed", "reasons", "message_key", "message")
    limited = build("block" => { "blocked" => true, "reason" => "ip_limit" })
    assert_equal ["error_limit_reached", nil], limited["eligibility"].values_at("message_key", "message")
    quantity = build("block" => { "blocked" => true, "reason" => "max_quantity", "message" => "Max 5 items." })
    assert_equal ["error_max_quantity", "Max 5 items."], quantity["eligibility"].values_at("message_key", "message")
  end

  def partial_rule(overrides = {})
    { "id" => 17, "amount" => "1000.0", "amount_type" => "fixed", "is_enabled" => true, "position" => 0, "product_scope" => "all",
      "variant_scope" => "all", "collection_scope" => "all", "discount_code" => "", "discount_value" => "0.0" }.merge(overrides)
  end

  def test_payment_options_with_a_matching_partial_rule
    quote = build("partial_rules" => [partial_rule], "money_format" => HUF, "cod_fee" => FEE)
    options = quote["payment_options"]
    assert_equal "cod", options["default_id"]
    assert_equal %w[cod rule_17], options["options"].map { |o| o["id"] }
    assert_equal [0, 398_900, "Pay Ft3 989 on delivery"], options["options"][0].values_at("pay_now_cents", "pay_later_cents", "description")
    assert_equal [100_000, 298_900, "Pay Ft1 000 now and Ft2 989 on delivery"], options["options"][1].values_at("pay_now_cents", "pay_later_cents", "description")
    assert_nil build("partial_rules" => [partial_rule("min_cart_range" => "5000.0")])["payment_options"], "no matching rule, no step"
  end

  def test_rto_gating_removes_cod_and_keeps_partial_options
    general = E::Defaults.general.merge("rto" => { "gating_enabled" => true, "block_band" => "high", "min_score" => nil, "message" => "Please pay a deposit." })
    input = { "general" => general, "partial_rules" => [partial_rule], "money_format" => HUF }
    high = build(input.merge("risk" => { "band" => "high", "score" => 81 }))
    assert_equal [false, ["rto_high_risk"], "Please pay a deposit.", true], high["eligibility"].values_at("cod_allowed", "reasons", "message", "pay_online")
    assert_equal ["rule_17"], high["payment_options"]["options"].map { |o| o["id"] }
    assert_equal "rule_17", high["payment_options"]["default_id"]
    medium = build(input.merge("risk" => { "band" => "medium", "score" => 55 }))
    assert medium["eligibility"]["cod_allowed"]
    by_score = build(input.merge("general" => general.merge("rto" => general["rto"].merge("min_score" => 50)), "risk" => { "band" => "medium", "score" => 55 }))
    refute by_score["eligibility"]["cod_allowed"]
    off = build("risk" => { "band" => "high", "score" => 99 })
    assert off["eligibility"]["cod_allowed"], "gating is off by default"
    no_rule = build("general" => general, "risk" => { "band" => "high", "score" => 81 })
    assert_nil no_rule["payment_options"]
  end

  def test_otp_required
    otp = { "shop_enabled" => true, "mode" => "before_order", "risk_band" => "medium", "verified" => false }
    assert build("otp" => otp)["otp_required"]
    refute build("otp" => otp.merge("verified" => true))["otp_required"]
    refute build("otp" => otp.merge("mode" => "order_first"))["otp_required"]
    risk_based = otp.merge("mode" => "risk_based")
    refute build("otp" => risk_based, "risk" => { "band" => "low", "score" => 5 })["otp_required"]
    assert build("otp" => risk_based, "risk" => { "band" => "medium", "score" => 50 })["otp_required"]
    refute build("otp" => risk_based, "risk" => nil)["otp_required"]
  end

  def test_stock_and_max_quantity
    scarce = build("lines" => [line("quantity" => 3, "inventory_quantity" => 2)])
    assert_equal [2, true], scarce["lines"].first.values_at("max_quantity", "available")
    assert_includes scarce["warnings"], "out_of_stock"
    oversell = build("lines" => [line("quantity" => 30, "inventory_policy" => "continue")])
    assert_nil oversell["lines"].first["max_quantity"]
    assert_equal [], oversell["warnings"]
    capped = build("lines" => [line("quantity" => 2)], "fraud" => E::Defaults.fraud.merge("max_quantity_per_order" => 5))
    assert_equal 5, capped["lines"].first["max_quantity"]
    sold_out = build("lines" => [line("available" => false)])
    assert_equal [false, ["out_of_stock"]], [sold_out["lines"].first["available"], sold_out["eligibility"]["reasons"]]
  end

  def test_digital_cart_needs_no_shipping
    quote = build("lines" => [line("requires_shipping" => false)])
    assert_equal [[], nil, 0, false], quote["shipping"].values_at("rates", "selected_id", "price_cents", "none_available")
    assert_nil quote["_draft"]["shipping"]
    assert_equal 199_900, quote["total_cents"]
  end

  def test_fingerprint_changes_with_the_priced_content_only
    base = build
    assert_match(/\A[0-9a-f]{64}\z/, base["_fingerprint"])
    assert_equal base["_fingerprint"], build["_fingerprint"]
    assert_equal base["_fingerprint"], build("contact" => {})["_fingerprint"]
    refute_equal base["_fingerprint"], build("lines" => [line("quantity" => 2)])["_fingerprint"]
    refute_equal base["_fingerprint"], build("cod_fee" => FEE)["_fingerprint"]
  end

  def test_input_is_not_mutated
    input = quote_input("lines" => [line("quantity" => 2)], "offers" => offers("quantity" => [quantity_offer]))
    snapshot = Marshal.load(Marshal.dump(input))
    Q.build(input)
    assert_equal snapshot, input
  end
end
