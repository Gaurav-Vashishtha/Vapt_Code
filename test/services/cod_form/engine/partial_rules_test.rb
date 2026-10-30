# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEnginePartialRulesTest < Minitest::Test
  include EngineTestHelper
  P = CodForm::Engine::PartialRules

  HUF = { "template" => "Ft{{amount}}", "decimals" => 0, "thousands" => " ", "decimal" => "," }.freeze
  TOTALS = { "subtotal_cents" => 599_700, "line_discount_cents" => 150_000, "merchandise_total_cents" => 449_700,
             "shipping_cents" => 149_000, "cod_fee_cents" => 50_000, "total_cents" => 648_700 }.freeze

  # PartialRuleSet#as_json: decimals arrive as strings.
  def rule(overrides = {})
    { "id" => 17, "rule_name" => "Advance", "amount" => "1000.0", "amount_type" => "fixed", "is_enabled" => true, "position" => 0,
      "product_scope" => "all", "product_ids" => [], "variant_scope" => "all", "variant_ids" => [],
      "collection_scope" => "all", "collection_ids" => [], "match_any_product" => false,
      "min_cart_range" => "0.0", "max_cart_range" => "0.0", "discount_code" => "", "discount_value" => "0.0",
      "discount_type" => "fixed", "sub_heading" => "", "description_template" => "", "amount_to_show" => "",
      "zipcode_blacklist_enabled" => false, "zipcode_blacklist" => "", "zipcode_whitelist_enabled" => false,
      "zipcode_whitelist" => "", "rto_engine" => nil, "cart_items_range" => nil, "phone_blacklist" => nil,
      "email_blacklist" => nil, "checkout_cod_only" => false }.merge(overrides)
  end

  def match(rules, cart: nil, address: { "zip" => "1051" }, contact: { "phone_digits" => "36301234567", "phone_national" => "301234567", "email" => "anna@example.com" }, risk: nil)
    cart ||= { "lines" => [line("quantity" => 3)], "total_cents" => 449_700, "total_quantity" => 3 }
    P.match(rules: rules, cart: cart, address: address, contact: contact, risk: risk).map { |r| r["id"] }
  end

  def test_position_order_and_disabled_rules
    rules = [rule("id" => 2, "position" => 1), rule("id" => 1, "position" => 0), rule("id" => 3, "is_enabled" => false)]
    assert_equal [1, 2], match(rules)
  end

  def test_cart_range_in_decimal_units
    assert_equal [17], match([rule("min_cart_range" => "4497.0", "max_cart_range" => "4497.0")])
    assert_equal [], match([rule("min_cart_range" => "4497.01")])
    assert_equal [], match([rule("max_cart_range" => "4496.99")])
    assert_equal [17], match([rule("min_cart_range" => "0.0", "max_cart_range" => "0.0")])
  end

  def test_product_scope
    mixed = { "lines" => [line, line("product_id" => "8222", "variant_id" => "44222", "collection_ids" => [])], "total_cents" => 1, "total_quantity" => 2 }
    assert_equal [17], match([rule("product_scope" => "include", "product_ids" => ["8111"])])
    assert_equal [], match([rule("product_scope" => "include", "product_ids" => ["8111"])], cart: mixed)
    assert_equal [17], match([rule("product_scope" => "include", "product_ids" => ["8111"], "match_any_product" => true)], cart: mixed)
    assert_equal [], match([rule("product_scope" => "exclude", "product_ids" => ["8222"])], cart: mixed)
    assert_equal [17], match([rule("product_scope" => "exclude", "product_ids" => ["1"])], cart: mixed)
  end

  def test_variant_and_collection_scope
    assert_equal [17], match([rule("variant_scope" => "include", "variant_ids" => ["44111"])])
    assert_equal [], match([rule("variant_scope" => "exclude", "variant_ids" => ["44111"])])
    assert_equal [17], match([rule("variant_scope" => "include", "variant_ids" => [])]), "empty list passes, as in the model"
    assert_equal [17], match([rule("collection_scope" => "include", "collection_ids" => ["301"])])
    assert_equal [], match([rule("collection_scope" => "include", "collection_ids" => ["999"])])
    assert_equal [], match([rule("collection_scope" => "exclude", "collection_ids" => ["301"])])
  end

  def test_cart_items_range
    assert_equal [17], match([rule("cart_items_range" => { "min_cart_items" => 3, "max_cart_items" => 3 })])
    assert_equal [], match([rule("cart_items_range" => { "min_cart_items" => 4 })])
    assert_equal [], match([rule("cart_items_range" => { "max_cart_items" => "2" })])
  end

  def test_zip_lists_are_skipped_while_the_zip_is_empty
    black = rule("zipcode_blacklist_enabled" => true, "zipcode_blacklist" => "1051, 2000-2999")
    white = rule("zipcode_whitelist_enabled" => true, "zipcode_whitelist" => "1000-1999")
    assert_equal [], match([black])
    assert_equal [], match([black], address: { "zip" => "2500" })
    assert_equal [17], match([black], address: { "zip" => "3000" })
    assert_equal [17], match([black], address: { "zip" => "" })
    assert_equal [17], match([white])
    assert_equal [], match([white], address: { "zip" => "2500" })
    assert_equal [17], match([white], address: {})
    assert_equal [17], match([rule("zipcode_blacklist_enabled" => false, "zipcode_blacklist" => "1051")])
  end

  def test_rto_engine
    gated = rule("rto_engine" => { "enabled" => true, "hide_at_band" => "high", "min_score" => 60 })
    assert_equal [17], match([gated], risk: { "band" => "medium", "score" => 59 })
    assert_equal [], match([gated], risk: { "band" => "high", "score" => 10 })
    assert_equal [], match([gated], risk: { "band" => "low", "score" => 60 })
    assert_equal [17], match([gated], risk: nil)
    assert_equal [17], match([rule("rto_engine" => { "enabled" => false, "hide_at_band" => "low" })], risk: { "band" => "high", "score" => 99 })
  end

  def test_buyer_blacklists
    assert_equal [], match([rule("phone_blacklist" => ["+36 30 123 4567"])])
    assert_equal [], match([rule("phone_blacklist" => ["301234567"])])
    assert_equal [], match([rule("email_blacklist" => ["ANNA@example.com"])])
    assert_equal [17], match([rule("phone_blacklist" => ["999"], "email_blacklist" => ["x@y.z"])])
  end

  def test_kind
    assert_equal "cod", P.kind(rule("amount_type" => "cod"))
    assert_equal "prepaid", P.kind(rule("amount_type" => "percentage", "amount" => "100.0"))
    assert_equal "partial", P.kind(rule("amount_type" => "percentage", "amount" => "30.0"))
    assert_equal "partial", P.kind(rule)
  end

  def test_amounts_fixed
    assert_equal({ "pay_now_cents" => 100_000, "pay_later_cents" => 548_700, "discount_cents" => 0 }, P.amounts(rule: rule, totals: TOTALS))
    capped = P.amounts(rule: rule("amount" => "99999.0"), totals: TOTALS)
    assert_equal [648_700, 0], capped.values_at("pay_now_cents", "pay_later_cents")
  end

  def test_amounts_percentage_uses_the_total_before_order_level_discounts
    result = P.amounts(rule: rule("amount_type" => "percentage", "amount" => "30.0"), totals: TOTALS)
    assert_equal 134_910, result["pay_now_cents"] # 30% of 599 700 - 150 000
    assert_equal 513_790, result["pay_later_cents"]
  end

  def test_amounts_with_a_rule_discount
    fixed = P.amounts(rule: rule("discount_code" => "PARTIAL5", "discount_value" => "500.0", "discount_type" => "fixed"), totals: TOTALS)
    assert_equal({ "pay_now_cents" => 100_000, "pay_later_cents" => 498_700, "discount_cents" => 50_000 }, fixed)
    percent = P.amounts(rule: rule("amount_type" => "percentage", "amount" => "100.0", "discount_code" => "PREPAID10",
                                   "discount_value" => "10.0", "discount_type" => "percentage"), totals: TOTALS)
    assert_equal({ "pay_now_cents" => 603_730, "pay_later_cents" => 0, "discount_cents" => 44_970 }, percent)
    no_code = P.amounts(rule: rule("discount_value" => "500.0"), totals: TOTALS)
    assert_equal 0, no_code["discount_cents"], "a discount needs a code"
  end

  def test_options_lists_cod_first_and_preselected
    rules = [rule, rule("id" => 18, "position" => 1, "amount_type" => "percentage", "amount" => "100.0"),
             rule("id" => 19, "position" => 2, "amount_type" => "cod", "amount" => "50.0")]
    options = P.options(rules: rules, totals: TOTALS, cod_allowed: true, money_format: HUF)
    assert_equal "cod", options["default_id"]
    assert_equal %w[cod rule_17 rule_18], options["options"].map { |o| o["id"] }
    assert_equal %w[cod partial prepaid], options["options"].map { |o| o["kind"] }
    cod = options["options"].first
    assert_equal ["payment_full_cod", 0, 648_700, "Pay Ft6 487 on delivery", nil], cod.values_at("title_key", "pay_now_cents", "pay_later_cents", "description", "rule_id")
    partial = options["options"][1]
    assert_equal ["payment_partial", 100_000, 548_700, "Pay Ft1 000 now and Ft5 487 on delivery", 17, 0],
                 partial.values_at("title_key", "pay_now_cents", "pay_later_cents", "description", "rule_id", "discount_cents")
    assert_equal ["payment_prepaid", "Pay Ft6 487 now (prepaid)"], options["options"][2].values_at("title_key", "description")
  end

  def test_options_without_cod
    options = P.options(rules: [rule], totals: TOTALS, cod_allowed: false, money_format: HUF)
    assert_equal ["rule_17"], options["options"].map { |o| o["id"] }
    assert_equal "rule_17", options["default_id"]
  end

  def test_options_are_nil_without_a_partial_or_prepaid_rule
    assert_nil P.options(rules: [], totals: TOTALS, cod_allowed: true, money_format: HUF)
    assert_nil P.options(rules: [rule("amount_type" => "cod")], totals: TOTALS, cod_allowed: true, money_format: HUF)
    assert_nil P.options(rules: [], totals: TOTALS, cod_allowed: false, money_format: HUF)
  end

  def test_description_sources
    assert_equal "Pay a little now", P.description(rule: rule("sub_heading" => "Pay a little now"), totals: TOTALS, money_format: HUF)
    custom = rule("description_template" => "{{pay_now}} now, {{pay_later}} later of {{total}} ({{cod_fee}} fee, {{discount}} off)")
    assert_equal "Ft1 000 now, Ft5 487 later of Ft6 487 (Ft500 fee, Ft0 off)", P.description(rule: custom, totals: TOTALS, money_format: HUF)
  end

  def test_handoff_attributes_for_a_partial_rule
    chosen = rule("discount_code" => "PARTIAL5", "discount_value" => "500.0")
    cart = TOTALS.merge("money_format" => HUF, "lines" => [
      { "variant_id" => "44111", "quantity" => 3, "discount_cents" => 150_000, "discount_title" => "3 packs", "image" => "https://cdn.example.com/w a.png" }
    ])
    result = P.handoff_attributes(rule: chosen, cart: cart, session: { "public_id" => "0b6c", "form_id" => 5 },
                                  dummy_variant_id: "45999", otp_phone_e164: "+36301234567", country: "hu")
    attributes = result["cart_attributes"]
    assert_equal "PARTIAL5", result["discount_code"]
    assert_equal ["0b6c", "5", "0b6c", "+36301234567", "HU"],
                 attributes.values_at("_codkFormSessionId", "_codkFormId", "_codkSessionId", "_otpVerifiedPhoneNumber", "_codkCountryCode")
    assert_equal ["fixed", "1000.0", "", ""], attributes.values_at("_codkAmountType", "_codkAmountValue", "_codkCheckoutMode", "_codkFinalDiscountValue")
    assert_equal "", attributes["_codkPrepaidDiscount"]
    assert_equal "Pay Ft1 000 now and Ft4 987 on delivery", attributes["_codkPaymentDescription"]
    assert_equal "44111:1500|3 packs,orderLevel:500|PARTIAL5", attributes["_codkDiscounts"]
    assert_equal "44111:https%3A%2F%2Fcdn.example.com%2Fw%20a.png", attributes["_codkImageURLs"]
    assert_equal ["5997", "45999", "[44111]", true], attributes.values_at("_codkOriginalTotal", "_partial_product_variant", "partial_payment_variants", "_partialPaymentProduct")
    refute attributes.key?("_codkBundleMode")
  end

  def test_handoff_attributes_without_otp_and_for_prepaid
    cart = TOTALS.merge("lines" => [{ "variant_id" => "44111", "quantity" => 1, "discount_cents" => 0 }])
    unverified = P.handoff_attributes(rule: rule, cart: cart, session: { "public_id" => "s", "form_id" => 5, "partial_expand_flow_enabled" => true },
                                      dummy_variant_id: nil, otp_phone_e164: nil, country: "HU")
    refute unverified["cart_attributes"].key?("_otpVerifiedPhoneNumber")
    refute unverified["cart_attributes"].key?("_partial_product_variant")
    assert_equal "expand", unverified["cart_attributes"]["_codkBundleMode"]
    assert_nil unverified["discount_code"]

    full = P.handoff_attributes(rule: rule("amount_type" => "percentage", "amount" => "100.0"), cart: cart, session: { "public_id" => "s", "form_id" => 5 },
                                dummy_variant_id: "45999", otp_phone_e164: nil, country: "HU")
    assert_nil full["cart_attributes"]["partial_payment_variants"]
    assert_equal true, full["cart_attributes"]["_partialPaymentProduct"]
    assert_equal "", full["cart_attributes"]["_codkPrepaidDiscount"]

    discounted = P.handoff_attributes(rule: rule("amount_type" => "percentage", "amount" => "100.0", "discount_code" => "PREPAID5", "discount_value" => "500.0"),
                                      cart: cart, session: { "public_id" => "s", "form_id" => 5 }, dummy_variant_id: nil, otp_phone_e164: nil, country: "HU")
    assert_equal "500|PREPAID5", discounted["cart_attributes"]["_codkPrepaidDiscount"]
    assert_equal "PREPAID5", discounted["discount_code"]

    pay_online = P.handoff_attributes(rule: nil, cart: TOTALS.merge("lines" => [{ "variant_id" => "44111", "quantity" => 2, "discount_cents" => 39_980, "discount_title" => "2 packs" }]),
                                      session: { "public_id" => "s", "form_id" => 5 }, dummy_variant_id: "45999", otp_phone_e164: nil, country: "HU")
    assert_equal({ "_codkFormSessionId" => "s", "_codkFormId" => "5", "_codkDiscounts" => "44111:399.8|2 packs" }, pay_online["cart_attributes"])
  end
end
