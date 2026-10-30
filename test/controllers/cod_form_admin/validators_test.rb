# frozen_string_literal: true

# Plain minitest, no Rails: ruby test/controllers/cod_form_admin/validators_test.rb
require "minitest/autorun"
require "json"
require_relative "../../../app/controllers/cod_form_admin/validators"
require_relative "../../../app/services/cod_form/engine/defaults"

class CodFormAdminValidatorsTest < Minitest::Test
  V = CodFormAdmin::Validators

  # ---- general (B.1.1) ---------------------------------------------------------------------------

  def test_general_fallback_defaults_equal_the_engine_defaults
    assert_equal CodForm::Engine::Defaults.general, V::General::FALLBACK_DEFAULTS
    assert_equal CodForm::Engine::Defaults.fraud, V::Fraud::FALLBACK_DEFAULTS
  end

  def test_general_complete_of_an_empty_config_is_the_default
    assert_equal CodForm::Engine::Defaults.general, V::General.complete({}, CodForm::Engine::Defaults.general)
    assert_equal CodForm::Engine::Defaults.general, V::General.complete(nil)
  end

  def test_general_partial_update_keeps_everything_else
    current = V::General.complete({ "countries" => ["HU"], "pages" => { "quick_buy" => true } })
    result = V::General.normalize({ "countries" => %w[hu co], "order_total" => { "max_cents" => 5_000_000 } }, current: current)
    assert_empty result["errors"]
    assert_equal %w[HU CO], result["value"]["countries"]
    assert_equal true, result["value"]["pages"]["quick_buy"]
    assert_equal 5_000_000, result["value"]["order_total"]["max_cents"]
    assert_nil result["value"]["order_total"]["min_cents"]
  end

  def test_general_unknown_keys_are_dropped
    result = V::General.normalize({ "hacker" => 1, "pages" => { "admin" => true } })
    assert_empty result["errors"]
    refute result["value"].key?("hacker")
    assert_equal %w[product cart drawer quick_buy], result["value"]["pages"].keys
  end

  def test_general_rejects_wrong_types_and_ranges
    result = V::General.normalize(
      { "countries" => ["Hungary"], "pages" => { "product" => "yes" },
      "products" => { "scope" => "some", "exclude_product_ids" => ["abc"] },
      "order_total" => { "min_cents" => 500, "max_cents" => 100 },
      "otp" => { "mode" => "never" }, "rto" => { "min_score" => 150 },
      "upsell_window_minutes" => 0, "embedded" => { "enabled" => true, "selector" => "<script>" } }
    )
    %w[general.countries general.pages.product general.products.scope general.products.exclude_product_ids
       general.order_total.max_cents general.otp.mode general.rto.min_score general.upsell_window_minutes
       general.embedded.selector].each do |path|
      assert result["errors"].key?(path), "expected an error at #{path}, got #{result['errors'].keys}"
    end
  end

  def test_general_selected_scope_needs_a_target
    result = V::General.normalize({ "products" => { "scope" => "selected" } })
    assert result["errors"].key?("general.products")
    ok = V::General.normalize({ "products" => { "scope" => "selected", "include_product_ids" => [8123, "gid://shopify/Product/9"] } })
    assert_empty ok["errors"]
    assert_equal %w[8123 9], ok["value"]["products"]["include_product_ids"]
  end

  def test_general_explicit_null_clears_a_value
    current = V::General.complete("order_total" => { "min_cents" => 100, "max_cents" => 900, "message" => "x" })
    result = V::General.normalize({ "order_total" => { "max_cents" => nil } }, current: current)
    assert_empty result["errors"]
    assert_nil result["value"]["order_total"]["max_cents"]
    assert_equal 100, result["value"]["order_total"]["min_cents"]
  end

  def test_general_recovery_discount
    assert V::General.normalize({ "abandonment" => { "recovery_discount" => { "type" => "percentage", "value" => 120 } } })["errors"].any?
    ok = V::General.normalize({ "abandonment" => { "recovery_discount" => { "type" => "percentage", "value" => 10 } } })
    assert_empty ok["errors"]
    assert_equal({ "type" => "percentage", "value" => 10 }, ok["value"]["abandonment"]["recovery_discount"])
  end

  def test_general_gated_features_only_when_turned_on
    old = V::General.complete({})
    new = V::General.normalize({ "otp" => { "mode" => "risk_based" }, "rto" => { "gating_enabled" => true },
                                 "branding" => { "hide_powered_by" => true } }, current: old)["value"]
    assert_equal %w[risk_based_otp rto_gating branding_removal], V::General.gated_features(old, new)
    assert_equal [], V::General.gated_features(new, new), "an already saved value never asks for the gate again"
    assert_equal [], V::General.gated_features(new, old), "turning a gated feature off is always allowed"
  end

  # ---- fraud (B.1.2) -----------------------------------------------------------------------------

  def test_fraud_defaults_and_partial_update
    assert_equal CodForm::Engine::Defaults.fraud, V::Fraud.complete({})
    result = V::Fraud.normalize({ "limits" => { "phone" => { "enabled" => true, "max_orders" => 2 } } }, current: {})
    assert_empty result["errors"]
    assert_equal({ "enabled" => true, "max_orders" => 2, "window_hours" => 24 }, result["value"]["limits"]["phone"])
    assert_equal 5, result["value"]["limits"]["ip"]["max_orders"]
    assert V::Fraud.enables_limit?(V::Fraud.complete({}), result["value"])
    refute V::Fraud.enables_limit?(result["value"], result["value"])
  end

  def test_fraud_rejects_bad_values
    result = V::Fraud.normalize({ "limits" => { "ip" => { "max_orders" => 0, "window_hours" => 10_000 } },
                                "max_quantity_per_order" => -1, "min_submit_seconds" => 600, "honeypot" => "on",
                                "blocked_message" => "x" * 301 })
    %w[fraud.limits.ip.max_orders fraud.limits.ip.window_hours fraud.max_quantity_per_order fraud.min_submit_seconds
       fraud.honeypot fraud.blocked_message].each { |path| assert result["errors"].key?(path), path }
  end

  # ---- shipping rate (C.3) -----------------------------------------------------------------------

  def test_shipping_rate_example_round_trips
    raw = {
      "id" => 4, "name" => "Standard delivery", "description" => "2–4 business days",
      "price_cents" => 149_000, "currency" => "HUF", "position" => 0, "active" => true, "source" => "manual",
      "conditions" => {
        "countries" => ["HU"], "provinces" => %w[HU-BU HU-PE],
        "subtotal_min_cents" => nil, "subtotal_max_cents" => 1_999_999,
        "weight_min_grams" => nil, "weight_max_grams" => 20_000,
        "quantity_min" => nil, "quantity_max" => nil,
        "products" => { "mode" => "any", "product_ids" => [], "collection_ids" => [] }
      }
    }
    result = V::ShippingRate.normalize(raw)
    assert_empty result["errors"]
    assert_equal raw.reject { |key, _| %w[id source].include?(key) }, result["value"]
  end

  def test_shipping_rate_minimal_and_errors
    ok = V::ShippingRate.normalize({ "name" => "Free", "price_cents" => 0 })
    assert_empty ok["errors"]
    assert_equal V::ShippingRate.empty_conditions, ok["value"]["conditions"]
    assert_nil ok["value"]["currency"]

    bad = V::ShippingRate.normalize({ "name" => " ", "price_cents" => -5, "currency" => "forint",
                                    "conditions" => { "provinces" => ["Budapest"], "quantity_min" => 5, "quantity_max" => 2,
                                                      "products" => { "mode" => "only" } } })
    %w[name price_cents currency conditions.provinces conditions.quantity_max conditions.products].each do |path|
      assert bad["errors"].key?(path), path
    end
  end

  def test_shipping_rate_partial_update
    current = V::ShippingRate.normalize({ "name" => "Standard", "price_cents" => 100, "conditions" => { "countries" => ["HU"] } })["value"]
    result = V::ShippingRate.normalize({ "price_cents" => 250, "active" => false }, current: current)
    assert_empty result["errors"]
    assert_equal "Standard", result["value"]["name"]
    assert_equal 250, result["value"]["price_cents"]
    assert_equal false, result["value"]["active"]
    assert_equal ["HU"], result["value"]["conditions"]["countries"]
  end

  # ---- offers (C.4) ------------------------------------------------------------------------------

  def quantity_offer(tiers: nil, **wrapper)
    { "offer_type" => "quantity", "name" => "Packs", "status" => "active",
      "targeting" => { "scope" => "selected", "product_ids" => %w[8111 8112], "collection_ids" => [] },
      "config" => {
        "title" => { "default" => "Buy more, save more" }, "layout" => "cards", "show_widget_on_product_page" => true,
        "tiers" => tiers || [
          { "quantity" => 3, "discount_type" => "unit_price", "value" => 149_900, "label" => { "default" => "3 packs" }, "badge" => { "default" => "" }, "image_url" => "", "preselected" => false },
          { "quantity" => 1, "discount_type" => "none", "value" => 0, "label" => { "default" => "1 pack" }, "badge" => { "default" => "" }, "image_url" => "", "preselected" => false },
          { "quantity" => 2, "discount_type" => "percentage", "value" => 10, "label" => { "default" => "2 packs" }, "badge" => { "default" => "Most popular" }, "image_url" => "", "preselected" => true }
        ],
        "apply_to_higher_quantities" => true
      } }.merge(wrapper.transform_keys(&:to_s))
  end

  def test_quantity_offer_valid_and_sorted_by_quantity
    result = V::Offer.normalize(quantity_offer)
    assert_empty result["errors"]
    assert_equal [1, 2, 3], result["value"]["config"]["tiers"].map { |tier| tier["quantity"] }
    assert_equal %w[offer_type name status priority targeting starts_at ends_at config], result["value"].keys
    assert_equal 0, result["value"]["priority"]
  end

  def test_quantity_offer_tier_limits
    six = (1..6).map { |n| { "quantity" => n, "discount_type" => "none" } }
    assert V::Offer.normalize(quantity_offer(tiers: six))["errors"].key?("config.tiers")
    assert V::Offer.normalize(quantity_offer(tiers: []))["errors"].key?("config.tiers")

    duplicate = [{ "quantity" => 2, "discount_type" => "none" }, { "quantity" => 2, "discount_type" => "none" }]
    assert V::Offer.normalize(quantity_offer(tiers: duplicate))["errors"].key?("config.tiers")

    two_pre = [{ "quantity" => 1, "preselected" => true }, { "quantity" => 2, "preselected" => true }]
    assert V::Offer.normalize(quantity_offer(tiers: two_pre))["errors"].key?("config.tiers")

    bad = [{ "quantity" => 0, "discount_type" => "percentage", "value" => 150 }, { "quantity" => 2, "discount_type" => "bogus" }]
    errors = V::Offer.normalize(quantity_offer(tiers: bad))["errors"]
    assert errors.key?("config.tiers[0].quantity")
    assert errors.key?("config.tiers[0].value")
    assert errors.key?("config.tiers[1].discount_type")
  end

  def test_offer_wrapper_errors
    errors = V::Offer.normalize({ "offer_type" => "bundle", "name" => "", "status" => "live",
                                "targeting" => { "scope" => "selected" }, "starts_at" => "tomorrow" })["errors"]
    %w[offer_type name status targeting starts_at].each { |path| assert errors.key?(path), path }

    schedule = V::Offer.normalize(quantity_offer(starts_at: "2026-10-05T00:00:00Z", ends_at: "2026-10-01T00:00:00Z"))
    assert schedule["errors"].key?("ends_at")
  end

  def test_offer_type_cannot_change_on_update
    current = V::Offer.normalize(quantity_offer)["value"]
    result = V::Offer.normalize({ "offer_type" => "bump", "name" => "Renamed" }, current: current)
    assert result["errors"].key?("offer_type")
    ok = V::Offer.normalize({ "name" => "Renamed" }, current: current)
    assert_empty ok["errors"]
    assert_equal "Renamed", ok["value"]["name"]
    assert_equal 3, ok["value"]["config"]["tiers"].size
  end

  def test_bump
    custom = { "offer_type" => "bump", "name" => "Express", "config" => { "title" => { "default" => "Add express handling" }, "kind" => "custom", "price_cents" => 49_900 } }
    result = V::Offer.normalize(custom)
    assert_empty result["errors"]
    assert_equal "before_totals", result["value"]["config"]["position"]
    assert_equal "draft", result["value"]["status"]
    assert_equal({ "scope" => "all", "product_ids" => [], "collection_ids" => [] }, result["value"]["targeting"])

    no_price = V::Offer.normalize(custom.merge("config" => { "title" => { "default" => "x" }, "kind" => "custom" }))
    assert no_price["errors"].key?("config.price_cents")
    no_variant = V::Offer.normalize(custom.merge("config" => { "title" => { "default" => "x" }, "kind" => "variant" }))
    assert no_variant["errors"].key?("config.variant_id")
    variant = V::Offer.normalize(custom.merge("config" => { "title" => "Gift wrap", "kind" => "variant", "variant_id" => 44_123 }))
    assert_empty variant["errors"]
    assert_equal "44123", variant["value"]["config"]["variant_id"]
    assert_equal({ "default" => "Gift wrap" }, variant["value"]["config"]["title"])
  end

  def test_downsell_upsell_threshold
    downsell = V::Offer.normalize({ "offer_type" => "downsell", "name" => "Exit", "config" => {} })
    assert_empty downsell["errors"]
    assert_equal 1, downsell["value"]["config"]["trigger_after_closes"]
    assert_equal "percentage", downsell["value"]["config"]["discount_type"]
    assert_equal 10, downsell["value"]["config"]["value"]
    assert_equal 0, downsell["value"]["config"]["timer_seconds"]

    assert V::Offer.normalize({ "offer_type" => "upsell", "name" => "Up", "config" => {} })["errors"].key?("config.variant_id")
    upsell = V::Offer.normalize({ "offer_type" => "upsell", "name" => "Up", "config" => { "variant_id" => "44123", "value" => 20 } })
    assert_empty upsell["errors"]
    assert_equal 120, upsell["value"]["config"]["timer_seconds"]

    assert V::Offer.normalize({ "offer_type" => "threshold", "name" => "Free", "config" => {} })["errors"].key?("config.threshold_cents")
    gift = V::Offer.normalize({ "offer_type" => "threshold", "name" => "Gift", "config" => { "kind" => "free_gift", "threshold_cents" => 1_500_000 } })
    assert gift["errors"].key?("config.gift_variant_id")
  end

  def test_offer_limits_and_gates
    assert_nil V::Offer.limit_error("quantity", 49)
    assert_match(/50/, V::Offer.limit_error("quantity", 50))
    assert_nil V::Offer.limit_error("bump", 19)
    assert_match(/20/, V::Offer.limit_error("bump", 20))
    assert_match(/1 active downsell/, V::Offer.limit_error("downsell", 1))
    assert_nil V::Offer.limit_error("upsell", 500)
    assert_equal %w[quantity_offers order_bumps upsell downsell threshold_offers],
                 %w[quantity bump upsell downsell threshold].map { |type| V::Offer::GATES[type] }
  end

  def test_off_2_product_overlap_and_collection_warnings
    mine = { "targeting" => { "scope" => "selected", "product_ids" => %w[1 2], "collection_ids" => ["77"] } }
    others = [
      { "id" => 5, "targeting" => { "scope" => "selected", "product_ids" => %w[2 3], "collection_ids" => [] } },
      { "id" => 6, "targeting" => { "scope" => "selected", "product_ids" => [], "collection_ids" => ["77"] } },
      { "id" => 7, "targeting" => { "scope" => "all", "product_ids" => [], "collection_ids" => [] } }
    ]
    assert_equal [{ "product_id" => "2", "offer_ids" => [5] }], V::Offer.product_conflicts(mine, others)
    assert_equal [], V::Offer.product_conflicts({ "targeting" => { "product_ids" => ["9"] } }, others)
    codes = V::Offer.overlap_warnings(mine, others).map { |warning| [warning["offer_id"], warning["code"]] }
    assert_equal [[5, "possible_collection_overlap"], [6, "collection_overlap"], [7, "all_products_overlap"]], codes
  end

  # ---- A/B tests (B.6) ---------------------------------------------------------------------------

  def test_ab_test
    ok = V::AbTest.normalize({ "name" => "Bump test", "offer_type" => "bump",
                             "variants" => [{ "key" => "a", "offer_id" => 12, "weight" => 50 }, { "key" => "control", "offer_id" => nil, "weight" => 50 }] })
    assert_empty ok["errors"]

    five = (1..5).map { |n| { "key" => "v#{n}", "offer_id" => n, "weight" => 20 } }
    assert V::AbTest.normalize({ "name" => "x", "offer_type" => "bump", "variants" => five })["errors"].key?("variants")
    bad = V::AbTest.normalize({ "name" => "x", "offer_type" => "bump",
                              "variants" => [{ "key" => "A!", "offer_id" => 1, "weight" => 60 }, { "key" => "b", "offer_id" => 2, "weight" => 60 }] })
    assert bad["errors"].key?("variants[0].key")
    assert bad["errors"].key?("variants")
  end

  # ---- pixels (C.6) ------------------------------------------------------------------------------

  def test_pixel
    result = V::Pixel.normalize({ "platform" => "tiktok", "pixel_id" => "C4ABCDEF123", "access_token" => " secret9f2a ",
                                "config" => { "purchase_event" => "lead", "events" => { "add_payment_info" => true } } })
    assert_empty result["errors"]
    assert_equal "secret9f2a", result["value"]["access_token"]
    assert_equal({ "form_open" => true, "add_payment_info" => true, "purchase" => true }, result["value"]["config"]["events"])
    assert_equal "lead", result["value"]["config"]["purchase_event"]
    assert_equal({ "scope" => "all", "product_ids" => [], "collection_ids" => [] }, result["value"]["targeting"])

    errors = V::Pixel.normalize({ "platform" => "myspace", "pixel_id" => "<x>" })["errors"]
    assert errors.key?("platform")
    assert errors.key?("pixel_id")
    assert V::Pixel.normalize({ "platform" => "google_ads", "pixel_id" => "123" })["errors"].key?("pixel_id")
  end

  def test_pixel_update_keeps_the_token_unless_sent
    current = { "platform" => "meta", "pixel_id" => "123", "enabled" => true, "position" => 0,
                "targeting" => { "scope" => "all", "product_ids" => [], "collection_ids" => [] }, "config" => {} }
    kept = V::Pixel.normalize({ "enabled" => false }, current: current)
    assert_empty kept["errors"]
    refute kept["value"].key?("access_token")
    cleared = V::Pixel.normalize({ "access_token" => "" }, current: current)
    assert cleared["value"].key?("access_token")
    assert_nil cleared["value"]["access_token"]
    assert V::Pixel.normalize({ "platform" => "tiktok" }, current: current)["errors"].key?("platform")
  end

  def test_pixel_gates_and_mask
    meta = { "platform" => "meta", "targeting" => { "scope" => "all" } }
    assert_equal ["first_pixel"], V::Pixel.required_features(meta, others_on_platform: 0)
    assert_equal ["extra_pixels"], V::Pixel.required_features(meta, others_on_platform: 2)
    assert_equal %w[first_pixel pixels_p3], V::Pixel.required_features({ "platform" => "snapchat" }, others_on_platform: 0)
    assert_equal %w[extra_pixels pixels_p3],
                 V::Pixel.required_features(meta.merge("targeting" => { "scope" => "selected" }), others_on_platform: 1)
    assert_equal 5, V::Pixel::MAX_PER_PLATFORM
    assert_equal "••••9f2a", V::Pixel.mask_token("EAAGsecret9f2a")
    assert_equal "••••", V::Pixel.mask_token("short")
    assert_nil V::Pixel.mask_token(nil)
  end

  # ---- block entries (C.5) -----------------------------------------------------------------------

  def test_block_entries_prepare
    result = V::BlockEntries.prepare(kind: "phone", existing: ["36301234567"],
                                     values: ["+36 30 123 4567", "0036 30 999 8888", "abc", "+36309998888", "06 20 555 1111"])
    assert_empty result["errors"]
    assert_equal [{ "value" => "0036 30 999 8888", "value_normalized" => "36309998888" },
                  { "value" => "06 20 555 1111", "value_normalized" => "6205551111" }], result["entries"]
    assert_equal 3, result["skipped"]
    assert_equal 1, result["invalid"]
  end

  def test_block_entries_kinds
    emails = V::BlockEntries.prepare(kind: "email", existing: [], values: ["  A@X.com ", "*@spam.io", "nope"])
    assert_equal %w[a@x.com *@spam.io], emails["entries"].map { |entry| entry["value_normalized"] }
    ips = V::BlockEntries.prepare(kind: "ip", existing: [], values: ["10.0.0.1", "10.0.0.0/24", "2001:db8::1", "999.1.1.1", "evil.com"])
    assert_equal ["10.0.0.1", "10.0.0.0/24", "2001:db8::1"], ips["entries"].map { |entry| entry["value_normalized"] }
    assert V::BlockEntries.prepare(kind: "name", existing: [], values: ["x"])["errors"].key?("kind")
    assert V::BlockEntries.prepare(kind: "ip", existing: [], values: [])["errors"].key?("values")
  end

  def test_block_entries_limit_of_5000_per_kind
    existing = (1..4_998).map { |n| format("3630%07d", n) }
    values = (1..5).map { |n| format("+3670%07d", n) }
    result = V::BlockEntries.prepare(kind: "phone", existing: existing, values: values)
    assert_equal 2, result["entries"].size
    assert_equal 3, result["over_limit"]
    assert_equal 3, result["skipped"]

    too_many = V::BlockEntries.prepare(kind: "phone", existing: [], values: Array.new(5_001, "+36301234567"))
    assert too_many["errors"].key?("values")
  end

  # ---- form draft pre-check (C.2) ----------------------------------------------------------------

  def test_default_form_passes_the_structural_check
    assert_empty V::FormDraft.errors(CodForm::Engine::Defaults.form_config)
  end

  def test_unknown_block_and_field_types_are_rejected
    config = CodForm::Engine::Defaults.form_config
    config["blocks"] << { "id" => "x", "type" => "iframe", "enabled" => true, "settings" => {} }
    config["fields"] << { "key" => "cf_ab12cd34", "type" => "file" }
    config["fields"] << { "key" => "ssn", "type" => "text" }
    config["fields"] << { "key" => "phone", "type" => "select" }
    errors = V::FormDraft.errors(config)
    assert errors.key?("draft_config.blocks[#{config['blocks'].size - 1}].type")
    assert errors.key?("draft_config.fields[#{config['fields'].size - 3}].type")
    assert errors.key?("draft_config.fields[#{config['fields'].size - 2}].key")
    assert errors.key?("draft_config.fields[#{config['fields'].size - 1}].type")
    assert errors.key?("draft_config.fields"), "duplicate phone key"
  end

  def test_custom_field_types_and_oversized_drafts
    config = CodForm::Engine::Defaults.form_config
    config["fields"] << { "key" => "cf_ab12cd34", "type" => "select", "options" => [] }
    assert_empty V::FormDraft.errors(config)
    assert V::FormDraft.custom_fields?(config)
    refute V::FormDraft.custom_fields?(CodForm::Engine::Defaults.form_config)

    assert V::FormDraft.errors("texts" => { "en" => { "title" => "x" * 301 } }).key?("draft_config.texts.en.title")
    assert V::FormDraft.errors("blocks" => Array.new(41) { |n| { "id" => "b#{n}", "type" => "image" } }).key?("draft_config.blocks")
    assert V::FormDraft.errors("mode" => "fullscreen").key?("draft_config.mode")
    assert V::FormDraft.errors("nope").key?("draft_config")
  end

  def test_apply_template_replaces_design_and_block_order_only
    config = CodForm::Engine::Defaults.form_config
    config["blocks"].insert(2, { "id" => "promo", "type" => "rich_text", "enabled" => true, "settings" => {} })
    template = CodForm::Engine::Defaults.templates.find { |entry| entry["key"] == "minimal" }
    out = V::FormDraft.apply_template(config, template)
    ids = out["blocks"].map { |block| block["id"] }
    assert_equal "submit", ids.last
    assert_equal %w[contact address shipping order_summary quantity_offer bumps discount totals promo submit], ids
    assert_equal template["design"], out["design"]
    assert_equal config["fields"], out["fields"]
    refute_equal ids, config["blocks"].map { |block| block["id"] }, "the input is not mutated"
  end

  # ---- paging ------------------------------------------------------------------------------------

  def test_paging
    assert_equal 1, V::Paging.page(nil)
    assert_equal 1, V::Paging.page("-4")
    assert_equal 7, V::Paging.page("7")
    assert_equal({ "page" => 2, "pages" => 3, "count" => 101 }, V::Paging.meta(page: 2, per: 50, count: 101))
    assert_equal({ "page" => 1, "pages" => 1, "count" => 0 }, V::Paging.meta(page: 1, per: 50, count: 0))
  end
end
