# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineDefaultsTest < Minitest::Test
  include EngineTestHelper
  D = CodForm::Engine::Defaults

  def test_default_form_matches_the_product_decisions
    config = D.form_config
    by_key = config["fields"].to_h { |f| [f["key"], f] }
    assert_equal %w[first_name phone country address1 zip province], config["fields"].select { |f| f["enabled"] }.map { |f| f["key"] }
    refute by_key["email"]["enabled"]
    refute by_key["last_name"]["required"]
    assert_nil by_key["zip"]["required"]
    assert_equal "submit", config["blocks"].last["type"]
    refute config["blocks"].find { |b| b["id"] == "discount" }["enabled"]
    # no merchant overrides: an `en` override would beat the translated package defaults (G.7)
    assert_equal({}, config["texts"])
  end

  def test_each_call_returns_a_fresh_copy
    D.form_config["fields"].clear
    D.general["countries"] << "HU"
    D.fraud["limits"]["phone"]["enabled"] = true
    assert_equal 13, D.form_config["fields"].length
    assert_equal [], D.general["countries"]
    refute D.fraud["limits"]["phone"]["enabled"]
  end

  def test_other_defaults
    assert_equal "Buy with COD", D.button_config["button"]["labels"]["default"]
    assert_equal "Checkout with COD", D.button_config["button"]["cart"]["labels"]["default"]
    assert_equal %w[classic address_first minimal bold compact], D.templates.map { |t| t["key"] }
    assert(D.templates.all? { |t| t["blocks_order"].last == "submit" && t["blocks_order"].length == 9 })
    assert_equal [3, 3, 5], D.fraud["limits"].values_at("phone", "email", "ip").map { |l| l["max_orders"] }
    assert_equal [60, "grace", 10], D.plan_limits.first.values_at("monthly_cap", "at_cap_behaviour", "grace_orders")
    assert_equal %w[HU CO RS DO MA PE PK EG], D.plan_limits.last["country_group"]["country_codes"]
  end
end

class CodFormEngineFormConfigTest < Minitest::Test
  include EngineTestHelper
  F = CodForm::Engine::FormConfig

  def normalize(overrides = {})
    F.normalize(E::Defaults.form_config.merge(overrides))
  end

  def test_default_config_is_a_fixed_point
    result = normalize
    assert_equal [], result["errors"]
    assert_equal [], result["warnings"]
    assert_equal E::Defaults.form_config, result["config"]
    assert_equal E::Defaults.form_config, F.normalize({})["config"]
    assert_equal E::Defaults.form_config, F.normalize(nil)["config"]
  end

  def test_unknown_keys_are_dropped
    config = normalize("evil" => 1, "design" => E::Defaults.design.merge("javascript" => "x"))["config"]
    refute config.key?("evil")
    refute config["design"].key?("javascript")
  end

  def test_invalid_values_fall_back_with_errors
    result = normalize("mode" => "fullscreen", "design" => E::Defaults.design.merge("primary" => "red", "radius" => 999))
    assert_includes result["errors"], { "path" => "mode", "code" => "invalid_value" }
    assert_includes result["errors"], { "path" => "design.primary", "code" => "invalid_color" }
    assert_equal ["popup", "#111111", 40], [result["config"]["mode"], result["config"]["design"]["primary"], result["config"]["design"]["radius"]]
  end

  def test_submit_block_is_always_last_and_enabled
    blocks = E::Defaults.form_config["blocks"]
    shuffled = [blocks.last.merge("enabled" => false)] + blocks[0..-2] + [{ "id" => "rt1", "type" => "rich_text", "enabled" => true, "settings" => { "html" => "<p onclick=\"x\">Hi<script>alert(1)</script></p>" } }]
    result = normalize("blocks" => shuffled)["config"]["blocks"]
    assert_equal ["submit", true], result.last.values_at("type", "enabled")
    assert_equal 1, result.count { |b| b["type"] == "submit" }
    assert_equal "<p>Hi</p>", result.find { |b| b["id"] == "rt1" }["settings"]["html"]
  end

  def test_duplicate_and_unknown_blocks
    blocks = E::Defaults.form_config["blocks"]
    result = normalize("blocks" => blocks + [blocks.first, { "id" => "x", "type" => "hologram" }])
    assert_includes result["errors"].map { |e| e["code"] }, "duplicate_block"
    assert_includes result["warnings"].map { |e| e["code"] }, "unknown_block_type"
    assert_equal 9, result["config"]["blocks"].length
  end

  def test_missing_core_blocks_are_added
    result = normalize("blocks" => [{ "id" => "submit", "type" => "submit", "enabled" => true, "settings" => {} }])["config"]["blocks"]
    assert_equal 9, result.length
    assert_equal "submit", result.last["type"]
    assert(result.select { |b| b["type"] == "fields" }.all? { |b| b["enabled"] })
  end

  def test_phone_and_country_cannot_be_disabled
    fields = E::Defaults.form_config["fields"].map { |f| %w[phone country].include?(f["key"]) ? f.merge("enabled" => false, "required" => false) : f }
    result = normalize("fields" => fields)
    phone = result["config"]["fields"].find { |f| f["key"] == "phone" }
    assert_equal [true, true], phone.values_at("enabled", "required")
    assert_equal 2, result["warnings"].count { |w| w["code"] == "cannot_disable" }
  end

  def test_custom_fields_and_invalid_keys
    fields = E::Defaults.form_config["fields"] + [
      { "key" => "cf_a1b2c3d4", "type" => "select", "group" => "address", "enabled" => true, "required" => true,
        "options" => [{ "value" => "door", "label" => { "en" => "Leave at the door" } }], "validation" => {} },
      { "key" => "cf_SHOUT", "type" => "text" },
      { "key" => "cf_b1b2c3d4", "type" => "password" },
      { "key" => "first_name", "type" => "text" }
    ]
    result = normalize("fields" => fields)
    custom = result["config"]["fields"].find { |f| f["key"] == "cf_a1b2c3d4" }
    assert_equal ["select", true, "full", [{ "value" => "door", "label" => { "en" => "Leave at the door" } }]], custom.values_at("type", "required", "width", "options")
    assert_equal %w[duplicate_field invalid_key invalid_type], result["errors"].map { |e| e["code"] }.sort
    assert_equal 14, result["config"]["fields"].length
  end

  def test_field_order_is_kept_and_missing_built_ins_are_appended
    result = normalize("fields" => [{ "key" => "phone" }, { "key" => "first_name", "required" => false }])["config"]["fields"]
    assert_equal %w[phone first_name], result.first(2).map { |f| f["key"] }
    assert_equal 13, result.length
    refute result[1]["required"]
  end

  def test_validation_rules
    fields = E::Defaults.form_config["fields"].map do |f|
      f["key"] == "address1" ? f.merge("validation" => { "min" => 5, "max" => 50, "regex" => "^[A-Z", "latin_only" => true }) : f
    end
    result = normalize("fields" => fields)
    assert_includes result["errors"], { "path" => "fields[5].validation.regex", "code" => "invalid_regex" }
    assert_equal({ "min" => 5, "max" => 50, "latin_only" => true }, result["config"]["fields"][5]["validation"])
    long = E::Defaults.form_config["fields"].map { |f| f["key"] == "city" ? f.merge("validation" => { "regex" => "a" * 201 }) : f }
    assert_includes normalize("fields" => long)["errors"].map { |e| e["code"] }, "too_long"
  end

  def test_texts_limits
    result = normalize("texts" => { "en" => { "title" => "x" * 301, "BAD KEY" => "y" }, "not a locale!" => { "title" => "z" } })
    assert_equal 300, result["config"]["texts"]["en"]["title"].length
    assert_equal ["title"], result["config"]["texts"]["en"].keys
    assert_equal %w[invalid_locale too_long], result["errors"].map { |e| e["code"] }.sort
    many = (0...13).to_h { |i| ["l#{('a'.ord + i).chr}", { "title" => "t" }] }
    limited = normalize("texts" => many)
    assert_equal 12, limited["config"]["texts"].length
    assert_includes limited["errors"], { "path" => "texts", "code" => "too_many_locales" }
  end

  def test_thank_you
    ok = normalize("thank_you" => { "type" => "custom_url", "url" => "https://brand.hu/thanks?o={order_name}" })
    assert_equal [], ok["errors"]
    assert_equal "https://brand.hu/thanks?o={order_name}", ok["config"]["thank_you"]["url"]
    bad = normalize("thank_you" => { "type" => "custom_url", "url" => "javascript:alert(1)" })
    assert_includes bad["errors"], { "path" => "thank_you.url", "code" => "invalid_url" }
    assert_equal "", bad["config"]["thank_you"]["url"]
    whatsapp = normalize("thank_you" => { "type" => "whatsapp", "whatsapp" => { "phone" => "" } })
    assert_includes whatsapp["errors"], { "path" => "thank_you.whatsapp.phone", "code" => "required" }
    assert_equal "order_status", normalize("thank_you" => { "type" => "fireworks" })["config"]["thank_you"]["type"]
  end

  def test_for_storefront_reduces_texts
    config = E::Defaults.form_config.merge("texts" => { "en" => { "title" => "A" }, "hu" => { "title" => "B" }, "fr" => { "title" => "C" } })
    assert_equal %w[en hu], F.for_storefront(config, locale: "hu-HU")["texts"].keys
    assert_equal %w[en], F.for_storefront(config, locale: "de")["texts"].keys
    assert_equal 3, config["texts"].length, "input untouched"
  end

  def test_sanitize_html
    assert_equal %(<a href="https://x.y/z" target="_blank" rel="noopener noreferrer">ok</a>), F.sanitize_html(%(<a href="https://x.y/z" onclick="x()">ok</a>))
    assert_equal "<a>bad</a>", F.sanitize_html(%(<a href="http://x.y">bad</a>))
    assert_equal "<a>bad</a>", F.sanitize_html(%(<a href="javascript:alert(1)">bad</a>))
    assert_equal "1 &lt; 2 <br><b>b</b>", F.sanitize_html("1 < 2 <br/><b style=\"x\">b</b><img src=x onerror=y>")
    assert_equal "", F.sanitize_html("<script>alert(1)</script><style>p{}</style>")
  end
end

class CodFormEngineFormValidatorTest < Minitest::Test
  include EngineTestHelper
  V = CodForm::Engine::FormValidator

  def test_fixture_cases
    data = fixture("validation_cases")
    data["cases"].each do |c|
      schema = E::CountrySchema.for(country: c["country"], data: countries)
      # Cases with "has_provinces" use the schema as the server sends it: province mode resolved.
      schema = E::CountrySchema.resolve(schema, has_provinces: c["has_provinces"]) if c.key?("has_provinces")
      result = V.validate(config: data["config"], schema: schema, values: c["values"])
      assert_equal c["fields"], result["fields"], c["name"]
      assert_equal c["fields"].empty?, result["valid"], c["name"]
    end
  end

  # CountrySchema.resolve: the province field is a select fed by a list, or it does not exist.
  def test_resolved_province_mode
    resolve = ->(country, has) { E::CountrySchema.resolve(E::CountrySchema.for(country: country, data: countries), has_provinces: has) }
    mode = ->(schema) { schema.dig("address", "province").values_at("mode", "declared_mode") }
    assert_equal %w[hidden auto], mode.call(resolve.call("KE", false))   # default schema, no list
    assert_equal %w[select auto], mode.call(resolve.call("MA", true))    # auto + list
    assert_equal %w[hidden auto], mode.call(resolve.call("MA", false))
    assert_equal %w[select select], mode.call(resolve.call("IN", true))
    assert_equal %w[hidden select], mode.call(resolve.call("AE", false)) # select without a list: nothing to choose from
    assert_equal %w[hidden hidden], mode.call(resolve.call("HU", true))  # hidden stays hidden
    # idempotent, and it never mutates its input
    original = E::CountrySchema.for(country: "MA", data: countries)
    once = E::CountrySchema.resolve(original, has_provinces: true)
    assert_equal once, E::CountrySchema.resolve(once, has_provinces: true)
    assert_equal %w[hidden auto], mode.call(E::CountrySchema.resolve(once, has_provinces: false))
    assert_equal "auto", original.dig("address", "province", "mode")
    assert_equal "Region", once.dig("address", "province", "label")
    # the default form requires `province`; a hidden one must never fail validation
    values = { "first_name" => "Anna", "phone" => "712345678", "country" => "KE", "address1" => "Moi Avenue 1", "city" => "Nairobi" }
    assert V.validate(config: E::Defaults.form_config, schema: resolve.call("KE", false), values: values)["valid"]
    assert_equal({ "province" => "error_province" },
                 V.validate(config: E::Defaults.form_config, schema: resolve.call("KE", true), values: values)["fields"])
  end

  def test_accepts_the_grouped_request_shape
    schema = E::CountrySchema.for(country: "HU", data: countries)
    values = { "contact" => { "first_name" => "Anna", "phone" => "301234567" },
               "address" => { "country" => "HU", "address1" => "Fo utca 1", "city" => "Budapest", "zip" => "" },
               "fields" => { "note" => "" }, "custom_fields" => {} }
    assert_equal({ "zip" => "error_zip" }, V.validate(config: E::Defaults.form_config, schema: schema, values: values)["fields"])
  end

  def test_disabled_fields_are_not_validated
    schema = E::CountrySchema.for(country: "HU", data: countries)
    values = { "first_name" => "Anna", "phone" => "301234567", "country" => "HU", "address1" => "Fo utca 1", "city" => "Budapest", "zip" => "1051", "email" => "not-an-email" }
    assert V.validate(config: E::Defaults.form_config, schema: schema, values: values)["valid"]
  end

  def test_custom_fields_regex_latin_only_and_consent
    config = E::Defaults.form_config
    config["fields"] = [
      { "key" => "cf_aaaaaaaa", "type" => "text", "enabled" => true, "required" => true, "validation" => { "latin_only" => true } },
      { "key" => "cf_bbbbbbbb", "type" => "select", "enabled" => true, "required" => false, "options" => [{ "value" => "a" }, { "value" => "b" }], "validation" => {} },
      { "key" => "cf_cccccccc", "type" => "text", "enabled" => true, "required" => false, "validation" => { "regex" => "^[0-9]{3}$" } },
      { "key" => "cf_dddddddd", "type" => "checkbox", "enabled" => true, "required" => true, "validation" => {} },
      { "key" => "cf_eeeeeeee", "type" => "date", "enabled" => true, "required" => false, "validation" => {} },
      { "key" => "note", "type" => "textarea", "enabled" => true, "required" => true, "validation" => { "max" => 5 } }
    ]
    bad = { "cf_aaaaaaaa" => "Анна", "cf_bbbbbbbb" => "z", "cf_cccccccc" => "12a", "cf_dddddddd" => false, "cf_eeeeeeee" => "tomorrow", "note" => "" }
    assert_equal({ "cf_aaaaaaaa" => "error_latin_only", "cf_bbbbbbbb" => "error_cf_bbbbbbbb", "cf_cccccccc" => "error_cf_cccccccc",
                   "cf_dddddddd" => "error_cf_dddddddd", "cf_eeeeeeee" => "error_cf_eeeeeeee", "note" => "error_required" },
                 V.validate(config: config, schema: {}, values: bad)["fields"])
    good = { "cf_aaaaaaaa" => "Ánna Kovács", "cf_bbbbbbbb" => "b", "cf_cccccccc" => "123", "cf_dddddddd" => true, "cf_eeeeeeee" => "2026-10-03", "note" => "ok" }
    assert V.validate(config: config, schema: {}, values: good)["valid"]
    assert_equal({ "note" => "error_pattern" }, V.validate(config: config, schema: {}, values: good.merge("note" => "too long"))["fields"])
  end

  def test_a_broken_or_slow_pattern_never_crashes
    config = { "fields" => [{ "key" => "cf_aaaaaaaa", "type" => "text", "enabled" => true, "required" => false, "validation" => { "regex" => "([" } }] }
    assert V.validate(config: config, schema: {}, values: { "cf_aaaaaaaa" => "x" })["valid"]
    slow = { "fields" => [{ "key" => "cf_aaaaaaaa", "type" => "text", "enabled" => true, "required" => false, "validation" => { "regex" => "^(a+)+$" } }] }
    result = V.validate(config: slow, schema: {}, values: { "cf_aaaaaaaa" => ("a" * 40) + "!" })
    assert_includes [true, false], result["valid"]
  end
end

class CodFormEngineFormTargetingTest < Minitest::Test
  include EngineTestHelper
  T = CodForm::Engine::FormTargeting

  FORMS = [
    { "id" => 1, "is_default" => true, "status" => "active", "position" => 0, "targeting" => {} },
    { "id" => 2, "is_default" => false, "status" => "active", "position" => 2, "targeting" => { "product_ids" => ["8111"], "collection_ids" => [] } },
    { "id" => 3, "is_default" => false, "status" => "active", "position" => 1, "targeting" => { "product_ids" => [], "collection_ids" => ["301"] } },
    { "id" => 4, "is_default" => false, "status" => "archived", "position" => 0, "targeting" => { "product_ids" => ["8111"] } }
  ].freeze

  def test_first_matching_form_by_position_else_default
    assert_equal 3, T.pick(forms: FORMS, cart: { "lines" => [line] }, requested_id: nil)["id"]
    assert_equal 2, T.pick(forms: FORMS, cart: { "lines" => [line("collection_ids" => [])] }, requested_id: nil)["id"]
    assert_equal 1, T.pick(forms: FORMS, cart: { "lines" => [line("product_id" => "1", "collection_ids" => [])] }, requested_id: nil)["id"]
    assert_equal 1, T.pick(forms: FORMS, cart: { "lines" => [] }, requested_id: nil)["id"]
  end

  def test_requested_form_only_for_test_sessions
    assert_equal 3, T.pick(forms: FORMS, cart: { "lines" => [line] }, requested_id: 2)["id"]
    assert_equal 2, T.pick(forms: FORMS, cart: { "lines" => [line] }, requested_id: 2, is_test: true)["id"]
    assert_equal 3, T.pick(forms: FORMS, cart: { "lines" => [line] }, requested_id: 4, is_test: true)["id"], "archived forms are never served"
    assert_nil T.pick(forms: [], cart: {}, requested_id: nil)
  end
end

class CodFormEngineButtonConfigTest < Minitest::Test
  include EngineTestHelper
  B = CodForm::Engine::ButtonConfig

  def test_defaults_are_a_fixed_point
    result = B.normalize(preset: "B", config: E::Defaults.button_config)
    assert_equal ["B", [], E::Defaults.button_config], result.values_at("preset", "errors", "config")
    assert_equal E::Defaults.button_config, B.normalize(preset: nil, config: nil)["config"]
    assert_equal "B", B.normalize(preset: nil, config: nil)["preset"]
  end

  def test_invalid_values
    config = E::Defaults.button_config
    config["button"]["style"].merge!("bg" => "blue", "animation" => "spin", "radius" => 500)
    config["button"]["placement"] = { "position" => "custom", "selector" => "<script>" }
    config["button"]["labels"] = { "default" => "", "hu" => "Fizetés utánvéttel" }
    result = B.normalize(preset: "Z", config: config.merge("extra" => 1))
    codes = result["errors"].map { |e| [e["path"], e["code"]] }
    assert_includes codes, %w[preset invalid_value]
    assert_includes codes, ["button.style.bg", "invalid_color"]
    assert_includes codes, ["button.style.animation", "invalid_value"]
    assert_includes codes, ["button.placement.selector", "invalid_selector"]
    assert_includes codes, ["button.labels.default", "required"]
    style = result["config"]["button"]["style"]
    assert_equal ["#1c1c1e", "none", 40], style.values_at("bg", "animation", "radius")
    assert_equal({ "default" => "Buy with COD", "hu" => "Fizetés utánvéttel" }, result["config"]["button"]["labels"])
    refute result["config"].key?("extra")
    assert_equal "B", result["preset"]
  end

  def test_valid_customisation_is_kept
    config = E::Defaults.button_config
    config["button"]["style"].merge!("bg" => "#FF0000", "animation" => "pulse", "icon" => "truck")
    config["theme"]["rename_buy_now"] = { "default" => "Buy with prepaid" }
    config["theme"]["rename_add_to_cart"] = { "default" => "Add to bag" }
    config["theme"]["rename_checkout"] = { "default" => "Pay online" }
    config["theme"]["hide"]["drawer_checkout"] = true
    config["theme"]["hide"]["wallets"] = true
    result = B.normalize(preset: "c", config: config)
    assert_equal [], result["errors"]
    assert_equal "C", result["preset"]
    assert_equal ["#ff0000", "pulse", "truck"], result["config"]["button"]["style"].values_at("bg", "animation", "icon")
    assert_equal "Buy with prepaid", result["config"]["theme"]["rename_buy_now"]["default"]
    assert result["config"]["theme"]["hide"]["wallets"]
    assert_equal ["Add to bag", "Pay online", ""], result["config"]["theme"].values_at("rename_add_to_cart", "rename_checkout", "rename_drawer_checkout").map { |label| label["default"] }
    assert result["config"]["theme"]["hide"]["drawer_checkout"]
  end
end

class CodFormEngineMetafieldPayloadTest < Minitest::Test
  include EngineTestHelper
  M = CodForm::Engine::MetafieldPayload

  def input(overrides = {})
    { "enabled" => true, "api" => "https://app.codking.tech/", "shop" => "brand.myshopify.com", "version" => 37,
      "general" => E::Defaults.general.merge("countries" => %w[hu CO]), "button" => { "preset" => "B", "config" => E::Defaults.button_config },
      "rules" => { "deny_product_ids" => ["8123"], "deny_vendors" => ["ACME"], "max_total_cents" => 5_000_000, "min_total_cents" => 0 },
      "quantity_offers" => [quantity_offer], "features" => %w[otp qty_offer], "cap_fallback" => false, "test_only" => false }.merge(overrides)
  end

  def test_shape
    payload = M.build(input)
    assert_equal %w[v enabled api shop cap_fallback test_only countries pages vis rules button theme features qo embedded prepaid_label rtl_locales lang preview], payload.keys
    assert_equal [37, true, "https://app.codking.tech", "brand.myshopify.com", %w[HU CO]], payload.values_at("v", "enabled", "api", "shop", "countries")
    assert_equal({ "product" => true, "cart" => true, "drawer" => true, "quick_buy" => false }, payload["pages"])
    assert_equal "B", payload["button"]["preset"]
    assert_equal "Buy with COD", payload["button"]["labels"]["default"]
    assert_equal %w[ar ur he fa], payload["rtl_locales"]
    assert_equal "", payload["lang"]
    assert_equal "hi", M.build(input("general" => E::Defaults.general.merge("language" => "hi")))["lang"]
    # COD King's English default label carries its translations; the merchant's own entries win.
    assert_equal "Acheter en paiement à la livraison", payload["button"]["labels"]["fr"]
    assert_equal "Checkout with COD".length, payload["button"]["cart"]["labels"]["default"].length
    assert JSON.generate(payload)
  end

  def test_rules_and_visibility_sections
    payload = M.build(input)
    assert_equal [["8123"], ["acme"], nil, 5_000_000, false], payload["rules"].values_at("hide_p", "hide_vendors", "min_cents", "max_cents", "overflow")
    assert_equal ["all", [], true, false], payload["vis"].values_at("scope", "exc_p", "hide_oos", "overflow")
  end

  def test_id_lists_are_capped_with_overflow
    many = (1..300).map(&:to_s)
    payload = M.build(input("rules" => { "deny_product_ids" => many },
                            "general" => E::Defaults.general.merge("products" => { "scope" => "selected", "include_product_ids" => many })))
    assert_equal [250, true], [payload["rules"]["hide_p"].length, payload["rules"]["overflow"]]
    assert_equal [250, true, "selected"], [payload["vis"]["inc_p"].length, payload["vis"]["overflow"], payload["vis"]["scope"]]
  end

  def test_quantity_offer_entry
    qo = M.build(input)["qo"]
    assert_equal 1, qo.length
    assert_equal [12, ["8111"], [], false, "cards"], qo.first.values_at("id", "p", "c", "all", "layout")
    assert_equal({ "q" => 3, "type" => "unit_price", "value" => 149_900, "label" => { "default" => "3 packs", "hi" => "3 पैक", "ar" => "3 عبوات", "fr" => "3 lots", "es" => "3 paquetes", "hu" => "3 csomag", "sr" => "3 pakovanja", "ur" => "3 پیک" }, "badge" => { "default" => "" }, "image" => "", "pre" => false },
                 qo.first["tiers"].last)
    hidden = quantity_offer("config" => quantity_offer["config"].merge("show_widget_on_product_page" => false))
    assert_equal [], M.build(input("quantity_offers" => [hidden]))["qo"]
  end
end
