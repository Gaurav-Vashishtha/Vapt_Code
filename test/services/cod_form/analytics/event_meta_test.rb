# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../../app/services/cod_form/analytics/event_meta"

class CodFormAnalyticsEventMetaTest < Minitest::Test
  M = CodForm::Analytics::EventMeta

  def test_taxonomy_is_exactly_the_documented_list
    expected = %w[
      cf_button_view cf_form_open cf_first_input cf_shipping_selected cf_submit_attempt cf_submit_error
      cf_order_created cf_form_close cf_prepaid_redirect cf_partial_handoff cf_prepaid_order
      cf_otp_sent cf_otp_verified cf_otp_bypassed cf_offer_view cf_offer_accept cf_downsell_shown cf_downsell_accept
      cf_upsell_view cf_upsell_accept cf_recovery_open cf_blocked cf_fallback cf_client_error
    ]
    assert_equal expected, M::EVENT_TYPES
    assert_equal 24, M::EVENT_TYPES.uniq.size
  end

  def test_server_events_are_never_accepted_from_the_browser
    server = %w[cf_form_open cf_order_created cf_prepaid_redirect cf_partial_handoff cf_prepaid_order cf_otp_sent
                cf_otp_verified cf_otp_bypassed cf_upsell_accept cf_blocked cf_recovery_open]
    assert_equal server.sort, M::SERVER_EVENT_TYPES.sort
    server.each { |type| refute M.browser_allowed?(type), type }
    %w[cf_button_view cf_first_input cf_shipping_selected cf_submit_attempt cf_submit_error cf_form_close cf_offer_view
       cf_offer_accept cf_downsell_shown cf_downsell_accept cf_upsell_view cf_fallback cf_client_error].each do |type|
      assert M.browser_allowed?(type), type
    end
    refute M.browser_allowed?("form_view")
    refute M.known?("checkout_initiated")
  end

  def test_base_meta_from_session
    session = {
      "country_code" => "hu", "device" => "mobile", "source" => "product", "cod_form_id" => 5, "is_test" => false,
      "attribution" => { "utm_campaign" => "autumn" }, "ab_assignments" => { "3" => "a" },
      "quote_snapshot" => { "lines" => [{ "product_id" => "8111" }, { "product_id" => "8111" }, { "product_id" => "8222" }] },
      "contact" => { "phone_e164" => "+36301234567" }
    }
    assert_equal(
      { "country" => "HU", "device" => "mobile", "source" => "product", "form_id" => "5",
        "product_ids" => %w[8111 8222], "utm_campaign" => "autumn", "ab" => { "3" => "a" } },
      M.base_from_session(session)
    )
    assert_equal true, M.base_from_session(session.merge("is_test" => true))["test"]
    assert_equal({}, M.base_from_session(nil))
  end

  def test_sanitize_drops_unknown_keys_and_pii_shaped_input
    clean = M.sanitize_client(
      "field" => "phone", "phone" => "+36301234567", "email" => "a@b.c", "value" => { "nested" => 1 },
      "country" => "hu", "device" => "Phone", "product_id" => 8111, "reason" => "x" * 500, "quantity" => 2
    )
    assert_equal %w[country field product_id product_ids quantity reason], clean.keys.sort
    assert_equal "HU", clean["country"]
    assert_equal ["8111"], clean["product_ids"]
    assert_equal 200, clean["reason"].length
    refute clean.key?("device"), "an unknown device is dropped"
  end

  def test_session_facts_win_over_browser_claims
    merged = M.merge({ "country" => "HU", "test" => true, "form_id" => "5" }, { "country" => "CO", "test" => false, "field" => "zip" })
    assert_equal "HU", merged["country"]
    assert_equal true, merged["test"]
    assert_equal "zip", merged["field"]
  end

  def test_merge_never_exceeds_twenty_keys
    client = M::CLIENT_META_KEYS.to_h { |key| [key, "v"] }
    assert_operator M.merge({ "source" => "cart", "form_id" => "1" }, client).size, :<=, 20
  end

  def test_button_view_field_round_trip
    field = M.button_view_field("country" => "hu", "device" => "mobile", "product_id" => "8111")
    assert_equal "HU|mobile|8111", field
    assert_equal({ "country" => "HU", "device" => "mobile", "product_id" => "8111" }, M.parse_button_view_field(field))
    assert_equal "||", M.button_view_field({})
    assert_equal "HU||", M.button_view_field("country" => "HU", "product_id" => "<script>")
  end

  def test_clamp_time
    now = Time.utc(2026, 10, 3, 12, 0, 0)
    assert_equal Time.utc(2026, 10, 3, 11, 58, 0), M.clamp_time("2026-10-03T11:58:00Z", now: now)
    assert_equal now, M.clamp_time("2030-01-01T00:00:00Z", now: now)
    assert_equal now, M.clamp_time("2026-09-01T00:00:00Z", now: now)
    assert_equal now, M.clamp_time("yesterday", now: now)
    assert_equal now, M.clamp_time(nil, now: now)
  end
end
