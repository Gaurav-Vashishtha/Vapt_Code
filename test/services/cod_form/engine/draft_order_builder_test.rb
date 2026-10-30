# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineDraftOrderBuilderTest < Minitest::Test
  include EngineTestHelper
  B = CodForm::Engine::DraftOrderBuilder
  Q = CodForm::Engine::Quote

  CONTACT = { "first_name" => "Anna", "last_name" => "Kiss", "phone_e164" => "+36301234567", "email" => "anna@example.com" }.freeze
  ADDRESS = { "country" => "HU", "province" => "BU", "city" => "Budapest", "zip" => "1051", "address1" => "Fő utca 1", "address2" => "" }.freeze

  def meta(overrides = {})
    { "shop_tags" => [], "verified" => true, "verification_tag" => "✅ COD-Verified", "session_id" => "0b6c9c2e", "form_id" => 5,
      "is_test" => false, "attribution" => { "utm_source" => "fb", "fbclid" => "" }, "custom_fields" => [{ "label" => "Delivery note", "value" => "Leave at the door" }],
      "customer_gid" => "gid://shopify/Customer/77", "note_fields" => { "gst_number" => "", "note" => "Ring twice" },
      "otp_phone_e164" => "+36301234567", "country" => "HU" }.merge(overrides)
  end

  def example_quote
    data = fixture("quote_cases")
    input = data["base_input"].merge(data["cases"][2]["input"])
    input["lines"] = [input["lines"].first.merge("properties" => { "Engraving" => "Anna" })]
    Q.build(input)
  end

  def build(quote = example_quote, meta_overrides = {}, contact: CONTACT, address: ADDRESS)
    B.build(quote: quote, contact: contact, address: address, meta: meta(meta_overrides))
  end

  def test_architecture_example
    input = build
    assert_equal %w[lineItems acceptAutomaticDiscounts appliedDiscount shippingLine shippingAddress billingAddress email phone purchasingEntity
                    presentmentCurrencyCode taxExempt note tags customAttributes], input.keys
    product, bump, fee = input["lineItems"]
    assert_equal({ "variantId" => "gid://shopify/ProductVariant/44111", "quantity" => 3,
                   "appliedDiscount" => { "valueType" => "FIXED_AMOUNT", "value" => 500.0, "title" => "3 packs", "description" => "3 packs" },
                   "customAttributes" => [{ "key" => "Engraving", "value" => "Anna" }] }, product)
    assert_equal({ "title" => "Express handling", "quantity" => 1, "originalUnitPriceWithCurrency" => { "amount" => "499.00", "currencyCode" => "HUF" },
                   "requiresShipping" => false, "taxable" => true, "customAttributes" => [{ "key" => "_codk_line", "value" => "bump:21" }] }, bump)
    assert_equal({ "title" => "Cash on delivery fee", "quantity" => 1, "originalUnitPriceWithCurrency" => { "amount" => "500.00", "currencyCode" => "HUF" },
                   "requiresShipping" => false, "taxable" => false, "customAttributes" => [{ "key" => "_codk_line", "value" => "cod_fee" }] }, fee)
    assert_equal({ "valueType" => "FIXED_AMOUNT", "value" => 499.6, "title" => "WELCOME10", "description" => "Discount code WELCOME10" }, input["appliedDiscount"])
    assert_equal({ "title" => "Standard delivery", "priceWithCurrency" => { "amount" => "1490.00", "currencyCode" => "HUF" } }, input["shippingLine"])
    assert_equal ["anna@example.com", "+36301234567", "HUF", false], input.values_at("email", "phone", "presentmentCurrencyCode", "taxExempt")
    assert_equal({ "customerId" => "gid://shopify/Customer/77" }, input["purchasingEntity"])
    assert_equal ["COD", "Created-From-COD-King", "codking_form", "✅ COD-Verified"], input["tags"]
    assert_equal "COD Form order\nNote: Ring twice", input["note"]
  end

  def test_order_total_equals_the_quote_total
    quote = example_quote
    @variant_prices = { "gid://shopify/ProductVariant/44111" => 199_900 }
    assert_equal quote["total_cents"], draft_total_cents(build(quote))
    assert_equal 648_640, quote["total_cents"]
  end

  def test_order_total_equals_the_quote_total_across_awkward_prices
    @variant_prices = { "gid://shopify/ProductVariant/44111" => 0, "gid://shopify/ProductVariant/44999" => 60_000 }
    downsell = { "id" => 30, "config" => { "discount_type" => "fixed_amount", "value" => 10_000, "title" => { "default" => "Wait!" } } }
    bump = { "id" => 21, "offer_type" => "bump", "status" => "active", "priority" => 0, "targeting" => { "scope" => "all" },
             "config" => { "title" => { "default" => "Case" }, "kind" => "variant", "variant_id" => "44999", "price_cents" => 49_999 } }
    code = { "code" => "TEN", "kind" => "percentage", "value" => 12.5, "applies_to" => { "all" => true } }
    general = E::Defaults.general.merge("discounts" => { "code_field_enabled" => true, "codes_combine_with_offers" => true })
    [[999, 3, 15], [1999, 7, 33.33], [12_345, 2, 7.5], [100, 1, 50], [333, 9, 10]].each do |price, quantity, percent|
      @variant_prices["gid://shopify/ProductVariant/44111"] = price
      offer = quantity_offer("config" => { "tiers" => [{ "quantity" => 1, "discount_type" => "percentage", "value" => percent, "label" => { "default" => "Deal" } }] })
      quote = Q.build(quote_input(
        "lines" => [line("unit_price_cents" => price, "quantity" => quantity)], "general" => general, "discount_code" => code,
        "downsell_offer_id" => 30, "offers" => { "quantity" => [offer], "bumps" => [bump], "downsell" => downsell, "thresholds" => [] },
        "selected_bumps" => [{ "offer_id" => 21, "quantity" => 1 }], "bump_catalog" => { "44999" => line("variant_id" => "44999", "product_id" => "8999", "unit_price_cents" => 60_000) },
        "cod_fee" => { "enabled" => true, "mode" => "percentage", "value" => 3, "label" => "COD", "taxable" => true, "fx_rate" => 1.0 }
      ))
      assert_equal quote["total_cents"], draft_total_cents(build(quote)), "price #{price} x #{quantity} at #{percent}%"
      assert_operator quote["merchandise_total_cents"], :>=, 0
    end
  end

  def test_percentage_value_type_only_when_the_per_unit_amount_is_exact
    exact = Q.build(quote_input("lines" => [line("quantity" => 2)], "offers" => { "quantity" => [quantity_offer], "bumps" => [], "downsell" => nil, "thresholds" => [] }))
    assert_equal({ "valueType" => "PERCENTAGE", "value" => 10.0, "title" => "2 packs", "description" => "2 packs" }, build(exact)["lineItems"].first["appliedDiscount"])
    @variant_prices = { "gid://shopify/ProductVariant/44111" => 199_900 }
    assert_equal exact["total_cents"], draft_total_cents(build(exact))
    inexact = Q.build(quote_input("lines" => [line("quantity" => 2, "unit_price_cents" => 999)], "offers" => { "quantity" => [quantity_offer], "bumps" => [], "downsell" => nil, "thresholds" => [] }))
    assert_equal ["FIXED_AMOUNT", 1.0], build(inexact)["lineItems"].first["appliedDiscount"].values_at("valueType", "value") # 99.9 -> 100 cents per unit
  end

  def test_custom_attributes
    attributes = build["customAttributes"]
    assert_equal [
      { "key" => "_codkFormSessionId", "value" => "0b6c9c2e" }, { "key" => "_codkFormId", "value" => "5" },
      { "key" => "_codkCodFee", "value" => "500.00" }, { "key" => "_codkSessionId", "value" => "0b6c9c2e" },
      { "key" => "_otpVerifiedPhoneNumber", "value" => "+36301234567" }, { "key" => "_codkCountryCode", "value" => "HU" },
      { "key" => "_codk_campaign_json", "value" => "{\"utm_source\":\"fb\"}" }, { "key" => "Delivery note", "value" => "Leave at the door" }
    ], attributes
  end

  def test_unverified_test_order_without_email_or_customer
    input = build(example_quote, { "verified" => false, "is_test" => true, "customer_gid" => nil, "attribution" => {}, "custom_fields" => [],
                                   "shop_tags" => ["vip", "COD"], "note_fields" => { "gst_number" => "27AAPFU0939F1ZV", "note" => "" } },
                  contact: CONTACT.merge("email" => " "))
    assert_nil input["email"]
    refute input.key?("purchasingEntity")
    assert_equal %w[COD Created-From-COD-King codking_form codking_form_test vip], input["tags"]
    keys = input["customAttributes"].map { |a| a["key"] }
    refute_includes keys, "_otpVerifiedPhoneNumber"
    refute_includes keys, "_codk_campaign_json"
    assert_includes input["customAttributes"], { "key" => "_codkFormTest", "value" => "true" }
    assert_equal "COD Form order\nGST: 27AAPFU0939F1ZV", input["note"]
  end

  def test_addresses
    input = build
    expected = { "firstName" => "Anna", "lastName" => "Kiss", "address1" => "Fő utca 1", "city" => "Budapest", "provinceCode" => "BU",
                 "countryCode" => "HU", "zip" => "1051", "phone" => "+36301234567" }
    assert_equal expected, input["shippingAddress"]
    assert_equal expected, input["billingAddress"]
    prefixed = build(example_quote, {}, address: ADDRESS.merge("province" => "HU-PE", "zip" => ""))
    assert_equal "PE", prefixed["shippingAddress"]["provinceCode"]
    refute prefixed["shippingAddress"].key?("zip")
  end

  def test_no_shipping_line_fee_or_discount_when_absent
    quote = Q.build(quote_input("lines" => [line("requires_shipping" => false)]))
    input = build(quote)
    refute input.key?("shippingLine")
    refute input.key?("appliedDiscount")
    assert_equal 1, input["lineItems"].length
    refute input["lineItems"].first.key?("appliedDiscount")
    assert_includes input["customAttributes"], { "key" => "_codkCodFee", "value" => "0.00" }
  end

  def test_gift_and_discounted_variant_bump_lines
    threshold = { "id" => 41, "offer_type" => "threshold", "status" => "active", "priority" => 0,
                  "config" => { "kind" => "free_gift", "threshold_cents" => 100_000, "gift_variant_id" => "44777" } }
    bump = { "id" => 21, "offer_type" => "bump", "status" => "active", "priority" => 0, "targeting" => { "scope" => "all" },
             "config" => { "title" => { "default" => "Case" }, "kind" => "variant", "variant_id" => "44999", "price_cents" => 49_900 } }
    catalog = { "44777" => line("variant_id" => "44777", "title" => "Sticker", "unit_price_cents" => 9900),
                "44999" => line("variant_id" => "44999", "unit_price_cents" => 60_000) }
    quote = Q.build(quote_input("offers" => { "quantity" => [], "bumps" => [bump], "downsell" => nil, "thresholds" => [threshold] },
                                "selected_bumps" => [{ "offer_id" => 21, "quantity" => 1 }], "bump_catalog" => catalog))
    _product, bump_item, gift_item = build(quote)["lineItems"]
    assert_equal ["gid://shopify/ProductVariant/44999", { "valueType" => "FIXED_AMOUNT", "value" => 101.0, "title" => "Case", "description" => "Case" },
                  [{ "key" => "_codk_line", "value" => "bump:21" }]], bump_item.values_at("variantId", "appliedDiscount", "customAttributes")
    assert_equal ["gid://shopify/ProductVariant/44777", "PERCENTAGE", 100.0, [{ "key" => "_codk_line", "value" => "gift:41" }]],
                 [gift_item["variantId"], gift_item["appliedDiscount"]["valueType"], gift_item["appliedDiscount"]["value"], gift_item["customAttributes"]]
    @variant_prices = { "gid://shopify/ProductVariant/44111" => 199_900, "gid://shopify/ProductVariant/44999" => 60_000, "gid://shopify/ProductVariant/44777" => 9900 }
    assert_equal quote["total_cents"], draft_total_cents(build(quote))
  end
end
