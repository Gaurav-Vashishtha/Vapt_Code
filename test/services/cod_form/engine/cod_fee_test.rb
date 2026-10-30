# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineCodFeeTest < Minitest::Test
  F = CodForm::Engine::CodFee

  def config(overrides = {})
    { "enabled" => true, "mode" => "fixed", "value" => 500.0, "label" => "COD charge", "taxable" => false, "fx_rate" => 1.0 }.merge(overrides)
  end

  def test_fixed_fee
    assert_equal({ "enabled" => true, "label" => "COD charge", "amount_cents" => 50_000, "taxable" => false },
                 F.compute(config: config, base_cents: 348_900))
    assert_equal 4950, F.compute(config: config("value" => "49.50"), base_cents: 0)["amount_cents"]
    assert_equal 1999, F.compute(config: config("value" => 19.99), base_cents: 0)["amount_cents"]
  end

  def test_fixed_fee_with_exchange_rate
    assert_equal 6125, F.compute(config: config("value" => 49.0, "fx_rate" => 1.25), base_cents: 0)["amount_cents"]
    assert_equal 1_950_000, F.compute(config: config("value" => 50.0, "fx_rate" => 389.99), base_cents: 0, currency: "HUF")["amount_cents"]
    assert_equal 1_949_950, F.compute(config: config("value" => 50.0, "fx_rate" => 389.99), base_cents: 0, currency: "EUR")["amount_cents"]
    assert_equal 50_000, F.compute(config: config, base_cents: 0, currency: "HUF")["amount_cents"]
  end

  def test_percentage_fee_is_rounded_to_half_a_unit
    fee = ->(value, base) { F.compute(config: config("mode" => "percentage", "value" => value), base_cents: base)["amount_cents"] }
    assert_equal 8700, fee.call(2.5, 348_900)   # 8722.5 -> 8723 -> 8700
    assert_equal 17_450, fee.call(5, 348_900)   # 17445 -> 17450
    assert_equal 10_500, fee.call(3, 349_900)   # 10497 -> 10500
    assert_equal 2000, fee.call(2, 100_000)
  end

  def test_percentage_fee_uses_the_discounted_base
    full = F.compute(config: config("mode" => "percentage", "value" => 2), base_cents: 399_800 + 149_000)["amount_cents"]
    discounted = F.compute(config: config("mode" => "percentage", "value" => 2), base_cents: 359_820 + 149_000)["amount_cents"]
    assert_equal 11_000, full        # 10 976 -> 11 000
    assert_equal 10_200, discounted  # 10 176.4 -> 10 176 -> 10 200
  end

  def test_disabled_or_zero
    off = { "enabled" => false, "label" => "COD charge", "amount_cents" => 0, "taxable" => false }
    assert_equal off, F.compute(config: config("enabled" => false), base_cents: 100)
    assert_equal off, F.compute(config: config("value" => 0), base_cents: 100)
    assert_equal off, F.compute(config: config("mode" => "percentage", "value" => 5), base_cents: 0)
    assert_equal 0, F.compute(config: {}, base_cents: 100)["amount_cents"]
  end

  def test_label_and_taxable
    assert_equal "Cash on delivery fee", F.compute(config: config("label" => "  "), base_cents: 0)["label"]
    assert_equal true, F.compute(config: config("taxable" => true), base_cents: 0)["taxable"]
  end
end

class CodFormEngineCodFeeCurrencyTest < Minitest::Test
  def test_currency_may_come_from_the_config
    config = { "enabled" => true, "mode" => "fixed", "value" => 50.0, "fx_rate" => 389.99, "currency" => "HUF" }
    assert_equal 1_950_000, CodForm::Engine::CodFee.compute(config: config, base_cents: 0)["amount_cents"]
  end
end
