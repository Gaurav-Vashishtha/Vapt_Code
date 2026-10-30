# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineSessionTokenTest < Minitest::Test
  T = CodForm::Engine::SessionToken
  SECRET = "0123456789abcdef0123456789abcdef"
  NOW = 1_790_000_000

  def issue(**overrides)
    T.issue(**{ secret: SECRET, shop_id: 42, session_id: "0b6c9c2e-aaaa", issued_at: NOW }.merge(overrides))
  end

  def test_round_trip
    token = issue
    assert_match(/\Av1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\z/, token)
    expected = { "ok" => true, "shop_id" => 42, "session_id" => "0b6c9c2e-aaaa", "issued_at" => NOW, "expires_at" => NOW + 7200, "test" => false }
    assert_equal expected, T.verify(secret: SECRET, token: token, now: NOW + 10)
    assert_equal token, issue, "deterministic"
  end

  def test_test_flag_and_ttl
    token = issue(test: true, ttl_seconds: 60)
    result = T.verify(secret: SECRET, token: token, now: NOW + 59)
    assert_equal [true, NOW + 60], result.values_at("test", "expires_at")
    assert_equal({ "ok" => false, "error" => "expired" }, T.verify(secret: SECRET, token: token, now: NOW + 60))
  end

  def test_bad_signature
    token = issue
    assert_equal "bad_signature", T.verify(secret: "another-secret", token: token, now: NOW)["error"]
    version, payload, signature = token.split(".")
    forged = Base64.urlsafe_encode64(JSON.generate("sid" => "x", "shp" => 1, "iat" => NOW, "exp" => NOW + 9999, "t" => false), padding: false)
    assert_equal "bad_signature", T.verify(secret: SECRET, token: [version, forged, signature].join("."), now: NOW)["error"]
    assert_equal "bad_signature", T.verify(secret: SECRET, token: [version, payload, "AAAA"].join("."), now: NOW)["error"]
  end

  def test_malformed
    ["", nil, "v1.abc", "v2.a.b", "v1..b", "v1.a.b.c", "v1.$$$.###"].each do |token|
      assert_equal({ "ok" => false, "error" => "malformed" }, T.verify(secret: SECRET, token: token, now: NOW), token.inspect)
    end
  end
end
