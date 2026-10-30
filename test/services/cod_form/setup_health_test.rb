# frozen_string_literal: true

# Plain minitest, no Rails: ruby test/services/cod_form/setup_health_test.rb
require_relative "support/plain_boot"
require_relative "../../../app/services/cod_form/engine/postal_matcher"
require_relative "../../../app/services/cod_form/setup_health"

class CodFormSetupHealthTest < Minitest::Test
  Health = CodForm::SetupHealth

  def healthy(overrides = {})
    {
      "mode" => "cod_form",
      "embed" => { "enabled" => true, "legacy_enabled" => false,
                   "theme_editor_url" => "https://brand.myshopify.com/admin/themes/current/editor?context=apps&activateAppId=uuid/cod-form-embed",
                   "legacy_theme_editor_url" => "https://brand.myshopify.com/admin/themes/current/editor?context=apps" },
      "express_active" => false, "shipping_rate_count" => 2, "countries" => ["HU"],
      "cap" => { "state" => "ok", "cap" => 60 }, "otp_bypassed_24h" => 0, "rule_cod_fee_ignored" => false,
      "allow_zip_patterns" => [], "cod_only_through_form" => false,
      "setup_state" => {}, "test_order_done" => false
    }.merge(overrides)
  end

  def codes(facts)
    Health.items(facts).map { |item| item["code"] }
  end

  def test_healthy_shop_has_no_items
    assert_equal [], Health.items(healthy)
  end

  def test_every_item_has_the_four_keys_and_a_known_code
    facts = healthy("embed" => healthy["embed"].merge("enabled" => false, "legacy_enabled" => true), "express_active" => true,
                    "shipping_rate_count" => 0, "countries" => [], "cap" => { "state" => "fallback", "cap" => 60 },
                    "otp_bypassed_24h" => 4, "rule_cod_fee_ignored" => true,
                    "allow_zip_patterns" => CodForm::Engine::PostalMatcher.parse("4000*, 1000-1999"))
    items = Health.items(facts)
    items.each do |item|
      assert_equal %w[code severity count action_url], item.keys
      assert_includes Health::CODES, item["code"]
      assert_includes %w[critical warning info], item["severity"]
    end
    assert_equal %w[embed_off no_shipping_rate cap_reached zip_allow_list_no_exact no_country
                    otp_unavailable legacy_embed_on rule_cod_fee_ignored], items.map { |item| item["code"] }
    assert_equal 4, items.find { |item| item["code"] == "otp_unavailable" }["count"]
    assert_equal 60, items.find { |item| item["code"] == "cap_reached" }["count"]
    assert_equal "/features/cod-fees", items.find { |item| item["code"] == "rule_cod_fee_ignored" }["action_url"]
    assert_equal "/features/cod-form/shipping", items.find { |item| item["code"] == "no_shipping_rate" }["action_url"]
  end

  def test_embed_off_is_critical_only_while_the_form_is_live
    off = healthy["embed"].merge("enabled" => false)
    assert_equal "critical", Health.items(healthy("embed" => off)).first["severity"]
    assert_equal "warning", Health.items(healthy("embed" => off, "mode" => "legacy")).first["severity"]
    assert_match(/activateAppId/, Health.items(healthy("embed" => off)).first["action_url"])
  end

  def test_unknown_embed_status_is_not_reported_as_off
    unknown = healthy["embed"].merge("enabled" => nil, "legacy_enabled" => nil)
    assert_equal [], Health.items(healthy("embed" => unknown))
  end

  def test_legacy_embed_warning_needs_express_to_be_in_use
    legacy = healthy["embed"].merge("legacy_enabled" => true)
    assert_equal [], codes(healthy("embed" => legacy, "express_active" => false))
    items = Health.items(healthy("embed" => legacy, "express_active" => true))
    assert_equal ["legacy_embed_on"], items.map { |item| item["code"] }
    assert_equal "info", items[0]["severity"]
    assert_equal healthy["embed"]["legacy_theme_editor_url"], items[0]["action_url"]
  end

  def test_cap_states
    assert_equal [%w[cap_reached critical]], Health.items(healthy("cap" => { "state" => "fallback", "cap" => 60 })).map { |i| [i["code"], i["severity"]] }
    assert_equal [%w[cap_reached warning]], Health.items(healthy("cap" => { "state" => "grace", "cap" => 60 })).map { |i| [i["code"], i["severity"]] }
    assert_equal [%w[cap_flagged info]], Health.items(healthy("cap" => { "state" => "flagged", "cap" => 500 })).map { |i| [i["code"], i["severity"]] }
    assert_equal [], Health.items(healthy("cap" => {}))
  end

  def test_zip_allow_list_without_exact_codes
    parse = ->(list) { CodForm::Engine::PostalMatcher.parse(list) }
    assert_equal ["zip_allow_list_no_exact"], codes(healthy("allow_zip_patterns" => parse.call("4000*")))
    assert_equal [], codes(healthy("allow_zip_patterns" => parse.call("4000*, 1051")))
    assert_equal [], codes(healthy("allow_zip_patterns" => parse.call("")))
    assert_equal [], codes(healthy("allow_zip_patterns" => parse.call("4000*"), "cod_only_through_form" => true))
  end

  def test_checklist
    assert_equal [{ "key" => "embed", "done" => true }, { "key" => "preset", "done" => false },
                  { "key" => "shipping_rate", "done" => true }, { "key" => "test_order", "done" => false }],
                 Health.checklist(healthy)
    done = Health.checklist(healthy("setup_state" => { "preset_chosen_at" => "2026-10-03T09:00:00Z", "test_order_at" => "2026-10-03T09:30:00Z" }))
    assert_equal [true, true, true, true], done.map { |step| step["done"] }
    fresh = Health.checklist(healthy("embed" => { "enabled" => nil }, "shipping_rate_count" => 0, "test_order_done" => true))
    assert_equal [false, false, false, true], fresh.map { |step| step["done"] }
  end
end
