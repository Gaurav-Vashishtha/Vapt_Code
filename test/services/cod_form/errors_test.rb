require "json"
# frozen_string_literal: true

# Plain minitest, no Rails:  ruby test/services/cod_form/errors_test.rb
require "minitest/autorun"
require_relative "../../../app/services/cod_form/errors"

class CodFormErrorsTest < Minitest::Test
  E = CodForm::Errors

  def test_every_code_of_the_architecture_table_has_its_status
    expected = {
      "invalid_request" => 400, "invalid_token" => 401, "token_expired" => 401,
      "origin_not_allowed" => 403, "module_disabled" => 403, "shop_not_found" => 404,
      "cap_reached" => 409, "total_changed" => 409, "already_processing" => 409,
      "upsell_expired" => 410, "validation_failed" => 422, "not_eligible" => 422, "blocked" => 422,
      "limit_reached" => 422, "bot_suspected" => 422, "no_shipping_rate" => 422, "out_of_stock" => 422,
      "discount_invalid" => 422, "otp_invalid" => 422, "otp_attempts_exceeded" => 422,
      "otp_required" => 428, "rate_limited" => 429, "otp_throttled" => 429, "order_failed" => 502,
      "kill_switch" => 503
    }
    expected.each { |code, status| assert_equal status, E.http_status(code), code }
  end

  def test_checkout_fallback_only_where_specified
    with_fallback = E::DEFINITIONS.select { |_, d| d[2] == "checkout" }.keys.sort
    assert_equal %w[cap_reached kill_switch module_disabled origin_not_allowed shop_not_found], with_fallback
  end

  def test_envelope_shape
    body = E.envelope("blocked")
    assert_equal false, body["ok"]
    assert_equal %w[code fallback fields message_key retry_after], body["error"].keys.sort
    assert_equal "blocked", body["error"]["code"]
    assert_equal "error_blocked", body["error"]["message_key"]
    assert_nil body["error"]["fallback"]
    assert_equal({}, body["error"]["fields"])
    assert_nil body["error"]["retry_after"]
  end

  def test_custom_message_is_present_only_when_configured
    refute E.envelope("blocked", message: "  ")["error"].key?("message")
    assert_equal "No COD for you", E.envelope("blocked", message: "No COD for you")["error"]["message"]
  end

  def test_bot_suspected_uses_the_generic_message
    assert_equal "error_generic", E.envelope("bot_suspected")["error"]["message_key"]
  end

  def test_extra_keys_are_merged_but_cannot_override_the_envelope
    body = E.envelope("total_changed", extra: { "quote" => { "total_cents" => 1 }, "ok" => true, "error" => "x" })
    assert_equal({ "total_cents" => 1 }, body["quote"])
    assert_equal false, body["ok"]
    assert_kind_of Hash, body["error"]
  end

  def test_api_error_carries_status_fields_and_retry_after
    error = E.build("validation_failed", fields: { "zip" => "error_zip" })
    assert_equal 422, error.http_status
    assert_equal({ "zip" => "error_zip" }, error.to_h["error"]["fields"])

    throttled = E.build("otp_throttled", retry_after: 42)
    assert_equal 429, throttled.http_status
    assert_equal 42, throttled.to_h["error"]["retry_after"]
  end

  def test_unknown_code_becomes_a_500
    error = E.build("something_else")
    assert_equal 500, error.http_status
    refute E.known?("something_else")
  end

  def test_invalid_item_is_a_400_without_leaking_detail
    error = E::InvalidItem.new("unknown_variant")
    assert_equal 400, error.http_status
    assert_equal "invalid_request", error.to_h["error"]["code"]
    refute_includes error.to_h.to_s, "unknown_variant"
  end

  def test_message_does_not_contain_the_custom_text
    # ApiError#message is what ends up in logs: it must be the code only.
    assert_equal "blocked", E.build("blocked", message: "secret merchant text").message
  end

  # The browser renders `message_key` (and the field text keys) through its text table: a key
  # that is not a storefront text shows as the generic error (ARCHITECTURE.md G.7).
  def test_every_message_key_is_a_storefront_text_key
    texts = JSON.parse(File.read(File.expand_path("../../../config/cod_form/default_texts.json", __dir__)))["en"]
    E::DEFINITIONS.each do |code, (_status, message_key, _fallback)|
      assert texts.key?(message_key), "#{code}: #{message_key} is not in config/cod_form/default_texts.json"
    end
    assert texts.key?(E::InvalidItem.new.to_h["error"]["fields"]["items"])
    assert_equal "error_no_shipping", E.envelope("no_shipping_rate")["error"]["message_key"]
    assert_equal "error_otp_attempts", E.envelope("otp_attempts_exceeded")["error"]["message_key"]
    assert_equal "error_otp_send", E.envelope("otp_throttled")["error"]["message_key"]
    assert_equal "error_not_eligible", E.envelope("not_eligible")["error"]["message_key"]
  end
end
