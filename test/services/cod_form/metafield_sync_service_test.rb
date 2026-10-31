# frozen_string_literal: true

# Plain minitest, no Rails: ruby test/services/cod_form/metafield_sync_service_test.rb
require_relative "support/plain_boot"
require "json"
require_relative "../../../app/services/cod_form/engine/metafield_payload"
require_relative "../../../app/services/cod_form/metafield_sync_service"

class CodFormMetafieldSyncServiceTest < Minitest::Test
  Service = CodForm::MetafieldSyncService

  ALL_GATES = %w[cod_form_core quantity_offers preset_a embedded_mode address_autocomplete discount_code_field
                 rto_gating branding_removal risk_based_otp order_bumps downsell upsell threshold_offers custom_fields]
              .each_with_object({}) { |key, out| out[key] = { "allowed" => true, "min_tier" => "free" } }.freeze

  # ARCHITECTURE.md C.1.1, verbatim.
  EXAMPLE = JSON.parse(<<~JSON)
    {
      "v": 37,
      "enabled": true,
      "api": "https://app.codking.tech",
      "shop": "brand.myshopify.com",
      "cap_fallback": false,
      "test_only": false,
      "countries": ["HU", "CO"],
      "pages": {"product": true, "cart": true, "drawer": true, "quick_buy": false},
      "vis": {
        "scope": "all",
        "inc_p": [], "inc_c": [], "exc_p": ["8123"], "exc_c": [],
        "min_cents": null, "max_cents": 5000000,
        "hide_oos": true,
        "overflow": false
      },
      "rules": {
        "hide_p": [], "show_p": [], "hide_v": [], "hide_c": [], "show_c": [],
        "hide_vendors": [], "show_vendors": [],
        "min_cents": null, "max_cents": null,
        "overflow": false
      },
      "button": {
        "preset": "B",
        "labels": {"default": "Buy with COD", "hu": "Fizetés utánvéttel"},
        "subtitles": {"default": ""},
        "style": {
          "bg": "#1c1c1e", "color": "#ffffff",
          "border_color": "#1c1c1e", "border_width": 0, "radius": 6,
          "shadow": "sm", "font_size": 16, "bold": true, "height": 50, "full_width": true,
          "icon": "cart", "animation": "none"
        },
        "placement": {"position": "below", "selector": ""},
        "sticky": {"enabled": true, "labels": {"default": "Buy with COD"}},
        "cart": {"enabled": false, "labels": {"default": "Checkout with COD"}, "selector": ""},
        "drawer": {"enabled": false, "labels": {"default": "Checkout with COD"}, "selector": ""},
        "quick_buy": {"enabled": false, "selector": ""}
      },
      "theme": {
        "rename_buy_now": {"default": ""},
        "rename_add_to_cart": {"default": ""},
        "rename_checkout": {"default": ""},
        "rename_drawer_checkout": {"default": ""},
        "hide": {"add_to_cart": false, "buy_now": false, "checkout": false, "drawer_checkout": false, "wallets": false}
      },
      "features": ["otp", "partial", "qty_offer", "pixels"],
      "qo": [
        {
          "id": 12, "p": ["8111", "8112"], "c": [], "all": false, "layout": "cards",
          "title": {"default": "Buy more, save more"},
          "tiers": [
            {"q": 1, "type": "none", "value": 0, "label": {"default": "1 pack"}, "badge": {"default": ""}, "image": "", "pre": false},
            {"q": 2, "type": "percentage", "value": 10, "label": {"default": "2 packs"}, "badge": {"default": "Most popular"}, "image": "", "pre": true},
            {"q": 3, "type": "unit_price", "value": 149900, "label": {"default": "3 packs"}, "badge": {"default": ""}, "image": "", "pre": false}
          ]
        }
      ],
      "embedded": {"enabled": false, "selector": "", "position": "after"},
      "prepaid_label": {"default": ""},
      "rtl_locales": ["ar", "ur", "he", "fa"],
      "preview": false
    }
  JSON

  def general
    {
      "countries" => %w[HU CO],
      "pages" => { "product" => true, "cart" => true, "drawer" => true, "quick_buy" => false },
      "products" => { "scope" => "all", "include_product_ids" => [], "include_collection_ids" => [],
                      "exclude_product_ids" => ["8123"], "exclude_collection_ids" => [] },
      "order_total" => { "min_cents" => nil, "max_cents" => 5_000_000, "message" => "" },
      "hide_out_of_stock" => true,
      "otp" => { "mode" => "before_order", "risk_band" => "medium" },
      "rto" => { "gating_enabled" => false },
      "discounts" => { "code_field_enabled" => false, "codes_combine_with_offers" => false },
      "branding" => { "hide_powered_by" => false },
      "autocomplete" => { "enabled" => false, "google_api_key" => "" },
      "embedded" => { "enabled" => false, "selector" => "", "position" => "after", "form_id" => nil }
    }
  end

  def quantity_offer
    {
      "id" => 12, "offer_type" => "quantity", "name" => "Packs", "status" => "active", "priority" => 0,
      "targeting" => { "scope" => "selected", "product_ids" => %w[8111 8112], "collection_ids" => [] },
      "config" => {
        "title" => { "default" => "Buy more, save more" }, "layout" => "cards", "show_widget_on_product_page" => true,
        "tiers" => [
          { "quantity" => 1, "discount_type" => "none", "value" => 0, "label" => { "default" => "1 pack" }, "badge" => { "default" => "" }, "image_url" => "", "preselected" => false },
          { "quantity" => 2, "discount_type" => "percentage", "value" => 10, "label" => { "default" => "2 packs" }, "badge" => { "default" => "Most popular" }, "image_url" => "", "preselected" => true },
          { "quantity" => 3, "discount_type" => "unit_price", "value" => 149_900, "label" => { "default" => "3 packs" }, "badge" => { "default" => "" }, "image_url" => "", "preselected" => false }
        ],
        "apply_to_higher_quantities" => true
      }
    }
  end

  def facts(overrides = {})
    {
      "available" => true, "mode_off" => false, "has_preview_token" => true,
      "api_host" => "app.codking.tech", "shop_domain" => "brand.myshopify.com", "version" => 37,
      "general" => general,
      "button" => { "preset" => "B", "config" => { "button" => { "labels" => { "default" => "Buy with COD", "hu" => "Fizetés utánvéttel" } } } },
      "rules" => {},
      "quantity_offers" => [quantity_offer],
      "active_offer_types" => ["quantity"],
      "gates" => ALL_GATES,
      "cap_state" => "ok",
      "otp_enabled" => true, "partial_enabled" => true, "has_pixels" => true,
      "published_forms" => [{ "blocks" => [{ "id" => "submit", "type" => "submit", "enabled" => true }],
                              "fields" => [{ "key" => "phone", "type" => "tel", "enabled" => true }] }],
      "shop_country" => "HU"
    }.merge(overrides)
  end

  def payload(overrides = {})
    CodForm::Engine::MetafieldPayload.build(Service.build_input(facts(overrides)))
  end

  def test_payload_equals_the_architecture_example
    assert_equal EXAMPLE, payload
    assert_equal JSON.generate(EXAMPLE), JSON.generate(payload), "key order must match the document too"
  end

  def test_input_has_exactly_the_engine_keys
    assert_equal %w[enabled api shop version general button rules quantity_offers features cap_fallback test_only].sort,
                 Service.build_input(facts).keys.sort
  end

  def test_disabled_when_not_available
    result = payload("available" => false)
    assert_equal false, result["enabled"]
    assert_equal false, result["test_only"]
  end

  def test_test_only_before_going_live_needs_a_preview_token
    result = payload("available" => false, "mode_off" => true, "has_preview_token" => true)
    assert_equal true, result["enabled"]
    assert_equal true, result["test_only"]

    result = payload("available" => false, "mode_off" => true, "has_preview_token" => false)
    assert_equal false, result["enabled"]
    assert_equal false, result["test_only"]
  end

  def test_cap_fallback
    assert_equal true, payload("cap_state" => "fallback")["cap_fallback"]
    assert_equal false, payload("cap_state" => "grace")["cap_fallback"]
    assert_equal false, payload("cap_state" => "flagged")["cap_fallback"]
    assert_equal false, payload("cap_state" => nil)["cap_fallback"]
  end

  def test_api_base
    assert_equal "https://app.codking.tech", Service.api_base("app.codking.tech/")
    assert_equal "https://app.codking.tech", Service.api_base("https://app.codking.tech")
    assert_equal "", Service.api_base(nil)
  end

  def test_gated_off_quantity_offers_are_absent
    gates = ALL_GATES.merge("quantity_offers" => { "allowed" => false, "min_tier" => "pro" })
    result = payload("gates" => gates)
    assert_equal [], result["qo"]
    refute_includes result["features"], "qty_offer"
  end

  def test_preset_a_falls_back_to_b_without_the_gate
    button = { "preset" => "A", "config" => {} }
    assert_equal "A", payload("button" => button)["button"]["preset"]
    assert_includes payload("button" => button)["features"], "preset_a"

    gates = ALL_GATES.merge("preset_a" => { "allowed" => false, "min_tier" => "pro" })
    result = payload("button" => button, "gates" => gates)
    assert_equal "B", result["button"]["preset"]
    refute_includes result["features"], "preset_a"
  end

  def test_gated_general_switches_are_turned_off_for_the_storefront_only
    stored = general.merge("embedded" => { "enabled" => true, "selector" => "#x", "position" => "before", "form_id" => nil },
                           "autocomplete" => { "enabled" => true, "google_api_key" => "k" },
                           "otp" => { "mode" => "risk_based", "risk_band" => "medium" })
    gates = ALL_GATES.merge("embedded_mode" => { "allowed" => false, "min_tier" => "pro" },
                            "address_autocomplete" => { "allowed" => false, "min_tier" => "pro" },
                            "risk_based_otp" => { "allowed" => false, "min_tier" => "pro" })
    input = Service.build_input(facts("general" => stored, "gates" => gates))
    assert_equal false, input["general"]["embedded"]["enabled"]
    assert_equal false, input["general"]["autocomplete"]["enabled"]
    assert_equal "before_order", input["general"]["otp"]["mode"]
    assert_equal true, stored["embedded"]["enabled"], "the stored configuration is not mutated"
    refute_includes input["features"], "embedded"
    refute_includes input["features"], "autocomplete"

    allowed = Service.build_input(facts("general" => stored))
    assert_equal true, allowed["general"]["embedded"]["enabled"]
    assert_includes allowed["features"], "embedded"
    assert_includes allowed["features"], "autocomplete"
  end

  def test_features_from_offers_forms_and_countries
    forms = [{ "blocks" => [{ "id" => "b1", "type" => "rich_text", "enabled" => true },
                            { "id" => "b2", "type" => "countdown", "enabled" => false }],
               "fields" => [{ "key" => "cf_ab12cd34", "type" => "text", "enabled" => true }] }]
    list = Service.features(facts(
                              "active_offer_types" => %w[quantity bump downsell upsell threshold],
                              "published_forms" => forms,
                              "general" => general.merge("countries" => %w[IN], "discounts" => { "code_field_enabled" => true })
                            ).merge("preset" => "B"))
    assert_equal %w[otp partial qty_offer bumps downsell upsell discount custom_fields content india threshold pixels], list
  end

  def test_features_respect_offer_gates
    gates = ALL_GATES.merge("order_bumps" => { "allowed" => false, "min_tier" => "pro" },
                            "threshold_offers" => { "allowed" => false, "min_tier" => "pro" })
    list = Service.features(facts("active_offer_types" => %w[bump threshold upsell], "gates" => gates).merge("preset" => "B"))
    refute_includes list, "bumps"
    refute_includes list, "threshold"
    assert_includes list, "upsell"
  end

  def test_india_feature_for_an_indian_shop_with_all_countries
    list = Service.features(facts("general" => general.merge("countries" => []), "shop_country" => "in").merge("preset" => "B"))
    assert_includes list, "india"
    refute_includes Service.features(facts.merge("preset" => "B")), "india"
  end

  def test_minimal_facts_do_not_raise
    result = CodForm::Engine::MetafieldPayload.build(Service.build_input({}))
    assert_equal false, result["enabled"]
    assert_equal "B", result["button"]["preset"]
    assert_equal [], result["features"]
  end
end
