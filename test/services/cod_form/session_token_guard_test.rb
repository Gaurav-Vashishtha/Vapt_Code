# frozen_string_literal: true

# Plain minitest, no Rails:  ruby test/services/cod_form/session_token_guard_test.rb
#
# Covers the security contract of the storefront session token as the API uses it:
# CodForm::Engine::SessionToken (WS2) + CodForm::Errors.token_failure (the mapping used by
# Api::Form::BaseController#authenticate_session!).
require "minitest/autorun"
require "json"
require "base64"
require "openssl"
require_relative "../../../app/services/cod_form/errors"
require_relative "../../../app/services/cod_form/engine/session_token"

class CodFormSessionTokenGuardTest < Minitest::Test
  T = CodForm::Engine::SessionToken
  SECRET = "0123456789abcdef0123456789abcdef"
  NOW = 1_790_000_000
  SID = "0b6c9c2e-1111-4222-8333-444455556666"

  def issue(shop_id: 7, issued_at: NOW, ttl: 7200, secret: SECRET, test: false)
    T.issue(secret: secret, shop_id: shop_id, session_id: SID, issued_at: issued_at, ttl_seconds: ttl, test: test)
  end

  def failure(token, shop_id: 7, now: NOW + 10, secret: SECRET)
    CodForm::Errors.token_failure(T.verify(secret: secret, token: token, now: now), shop_id: shop_id)
  end

  def test_valid_token_passes_and_carries_the_session
    token = issue
    result = T.verify(secret: SECRET, token: token, now: NOW + 10)
    assert_equal true, result["ok"]
    assert_equal SID, result["session_id"]
    assert_equal 7, result["shop_id"]
    assert_equal NOW, result["issued_at"]
    assert_equal NOW + 7200, result["expires_at"]
    assert_nil failure(token)
  end

  def test_token_format
    version, payload, signature = issue.split(".")
    assert_equal "v1", version
    assert_equal %w[exp iat shp sid t], JSON.parse(Base64.urlsafe_decode64(payload)).keys.sort
    assert_equal 32, Base64.urlsafe_decode64(signature).bytesize
  end

  def test_wrong_shop_is_rejected
    assert_equal "invalid_token", failure(issue(shop_id: 7), shop_id: 8)
    assert_equal "invalid_token", failure(issue(shop_id: 7), shop_id: nil)
  end

  def test_expired_token
    token = issue(ttl: 60)
    assert_nil failure(token, now: NOW + 59)
    assert_equal "token_expired", failure(token, now: NOW + 60)
    assert_equal "token_expired", failure(token, now: NOW + 86_400)
  end

  def test_tampered_payload_is_rejected
    version, payload, signature = issue(shop_id: 7).split(".")
    forged = JSON.parse(Base64.urlsafe_decode64(payload)).merge("shp" => 8, "exp" => NOW + 10**7)
    forged_payload = Base64.urlsafe_encode64(JSON.generate(forged), padding: false)
    assert_equal "invalid_token", failure([version, forged_payload, signature].join("."), shop_id: 8)
  end

  def test_tampered_signature_is_rejected
    version, payload, signature = issue.split(".")
    flipped = signature[0] == "A" ? "B#{signature[1..]}" : "A#{signature[1..]}"
    assert_equal "invalid_token", failure([version, payload, flipped].join("."))
    assert_equal "invalid_token", failure([version, payload, signature[0, 10]].join("."))
  end

  def test_token_signed_with_another_secret_is_rejected
    assert_equal "invalid_token", failure(issue(secret: "another-secret-another-secret-123"))
  end

  def test_unsigned_and_malformed_tokens_are_rejected
    payload = Base64.urlsafe_encode64(JSON.generate("sid" => SID, "shp" => 7, "iat" => NOW, "exp" => NOW + 7200, "t" => false), padding: false)
    ["", nil, "v1", "v1.#{payload}", "v1.#{payload}.", "v2.#{payload}.abc", "garbage", "v1..", "a.b.c.d",
     "v1.#{payload}.#{Base64.urlsafe_encode64('', padding: false)}"].each do |token|
      assert_equal "invalid_token", failure(token), token.inspect
    end
  end

  def test_none_algorithm_style_forgery_is_rejected
    # A signature computed over the payload with an empty key must not verify.
    version, payload, = issue.split(".")
    forged_sig = Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", "", "#{version}.#{payload}"), padding: false)
    assert_equal "invalid_token", failure([version, payload, forged_sig].join("."))
  end

  def test_test_flag_cannot_be_flipped
    version, payload, signature = issue(test: false).split(".")
    forged = JSON.parse(Base64.urlsafe_decode64(payload)).merge("t" => true)
    forged_payload = Base64.urlsafe_encode64(JSON.generate(forged), padding: false)
    assert_equal "invalid_token", failure([version, forged_payload, signature].join("."))
  end

  def test_token_failure_handles_non_hash_results
    assert_equal "invalid_token", CodForm::Errors.token_failure(nil, shop_id: 7)
    assert_equal "invalid_token", CodForm::Errors.token_failure({ "ok" => true, "shop_id" => 7, "session_id" => "" }, shop_id: 7)
  end
end
