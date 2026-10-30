# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineFraudTest < Minitest::Test
  include EngineTestHelper
  F = CodForm::Engine::Fraud

  CONTACT = { "phone_digits" => "36301234567", "phone_national" => "301234567", "email" => "Anna@Example.com" }.freeze
  TIMING = { "elapsed_ms" => 48_211, "token_age_ms" => 52_000, "honeypot_value" => "" }.freeze

  def fraud(overrides = {})
    E::Defaults.fraud.merge("blocked_message" => "Blocked.", "limit_message" => "Too many orders.",
                            "max_quantity_message" => "Too many items.").merge(overrides)
  end

  def check(fraud: self.fraud, entries: {}, counts: {}, contact: CONTACT, ip: "203.0.113.9", cart: { "total_quantity" => 1 },
            timing: TIMING, is_test: false)
    F.check(fraud: fraud, entries: entries, counts: counts, contact: contact, ip: ip, cart: cart, timing: timing, is_test: is_test)
  end

  def limits(kind, max)
    fraud("limits" => E::Defaults.fraud["limits"].merge(kind => { "enabled" => true, "max_orders" => max, "window_hours" => 24 }))
  end

  def test_clean_buyer
    assert_equal({ "ok" => true, "code" => nil, "reason" => nil, "message" => nil }, check)
  end

  def test_phone_block_list_matches_international_or_national_digits
    assert_equal %w[blocked phone_blocked Blocked.], check(entries: { "phone" => ["36301234567"] }).values_at("code", "reason", "message")
    assert_equal "phone_blocked", check(entries: { "phone" => ["301234567"] })["reason"]
    assert_equal "phone_blocked", check(entries: { "phone" => ["+36 30 123 4567"] })["reason"]
    assert_equal "phone_blocked", check(entries: { "phone" => ["0301234567"] })["reason"]
    assert check(entries: { "phone" => ["1234567"] })["ok"], "a partial number does not match"
  end

  def test_email_block_list
    assert_equal "email_blocked", check(entries: { "email" => ["anna@example.com"] })["reason"]
    assert_equal "email_blocked", check(entries: { "email" => ["*@example.com"] })["reason"]
    assert check(entries: { "email" => ["*@ample.com", "other@example.com"] })["ok"]
  end

  def test_ip_block_list_exact_and_cidr
    assert_equal "ip_blocked", check(entries: { "ip" => ["203.0.113.9"] })["reason"]
    assert_equal "ip_blocked", check(entries: { "ip" => ["203.0.113.0/24"] })["reason"]
    assert_equal "ip_blocked", check(entries: { "ip" => ["203.0.0.0/16"] })["reason"]
    assert check(entries: { "ip" => ["203.0.114.0/24", "10.0.0.0/8", "203.0.113.8"] })["ok"]
    assert_equal "ip_blocked", check(entries: { "ip" => ["0.0.0.0/0"] })["reason"]
  end

  def test_velocity_boundaries
    assert check(fraud: limits("phone", 3), counts: { "phone" => 2 })["ok"], "third order is allowed"
    hit = check(fraud: limits("phone", 3), counts: { "phone" => 3 })
    assert_equal ["limit_reached", "phone_limit", "Too many orders."], hit.values_at("code", "reason", "message")
    assert_equal "phone_limit", check(fraud: limits("phone", 3), counts: { "phone" => 4 })["reason"]
    assert_equal "email_limit", check(fraud: limits("email", 1), counts: { "email" => 1 })["reason"]
    assert check(fraud: limits("ip", 5), counts: { "ip" => 4 })["ok"]
    assert_equal "ip_limit", check(fraud: limits("ip", 5), counts: { "ip" => 5 })["reason"]
  end

  def test_disabled_limits_are_ignored
    assert check(counts: { "phone" => 99, "email" => 99, "ip" => 99 })["ok"]
    assert check(fraud: limits("email", 1), counts: { "email" => 5 }, contact: CONTACT.merge("email" => ""))["ok"], "no email, no email limit"
  end

  def test_max_quantity
    capped = fraud("max_quantity_per_order" => 5)
    assert check(fraud: capped, cart: { "total_quantity" => 5 })["ok"]
    over = check(fraud: capped, cart: { "total_quantity" => 6 })
    assert_equal ["limit_reached", "max_quantity", "Too many items."], over.values_at("code", "reason", "message")
    assert_equal "max_quantity", check(fraud: capped, cart: { "lines" => [line("quantity" => 4), line("quantity" => 2)] })["reason"]
    assert check(cart: { "total_quantity" => 500 })["ok"], "no limit by default"
  end

  def test_honeypot_and_minimum_time
    assert_equal %w[bot_suspected honeypot], check(timing: TIMING.merge("honeypot_value" => "http://spam")).values_at("code", "reason")
    assert check(fraud: fraud("honeypot" => false), timing: TIMING.merge("honeypot_value" => "x"))["ok"]
    assert_equal "too_fast", check(timing: TIMING.merge("elapsed_ms" => 2999))["reason"]
    assert_equal "too_fast", check(timing: TIMING.merge("token_age_ms" => 2999))["reason"]
    assert check(timing: TIMING.merge("elapsed_ms" => 3000, "token_age_ms" => 3000))["ok"]
    assert_nil check(timing: TIMING.merge("elapsed_ms" => 10))["message"]
    assert check(timing: nil, entries: {})["ok"], "no timing at quote time"
  end

  def test_test_mode_skips_lists_and_limits_but_not_max_quantity
    assert check(entries: { "phone" => ["36301234567"] }, is_test: true)["ok"]
    assert check(fraud: limits("phone", 1), counts: { "phone" => 9 }, is_test: true)["ok"]
    assert_equal "max_quantity", check(fraud: fraud("max_quantity_per_order" => 1), cart: { "total_quantity" => 2 }, is_test: true)["reason"]
  end

  def test_block_list_wins_over_limits
    result = check(fraud: limits("phone", 1), counts: { "phone" => 5 }, entries: { "email" => ["anna@example.com"] })
    assert_equal "email_blocked", result["reason"]
  end

  def test_mask
    assert_equal "+36•••••4567", F.mask("phone", "+36 30 123 4567")
    assert_equal "a•••@x.com", F.mask("email", "anna@x.com")
    assert_equal "203.0.•.•", F.mask("ip", "203.0.113.9")
    assert_equal "", F.mask("phone", "")
  end
end
