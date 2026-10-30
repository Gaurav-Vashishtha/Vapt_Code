# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineMoneyTest < Minitest::Test
  M = CodForm::Engine::Money

  def test_percent_of_rounds_half_up
    assert_equal 19_990, M.percent_of(199_900, 10)
    assert_equal 1, M.percent_of(5, 10)        # 0.5 -> 1
    assert_equal 0, M.percent_of(4, 10)        # 0.4 -> 0
    assert_equal 150, M.percent_of(999, 15)    # 149.85 -> 150
    assert_equal 8723, M.percent_of(348_900, 2.5) # 8722.5 -> 8723
    assert_equal 333, M.percent_of(1000, 33.33) # 333.3 -> 333
    assert_equal 0, M.percent_of(0, 50)
    assert_equal 1000, M.percent_of(1000, 100)
  end

  def test_percent_of_is_exact_with_decimal_percentages
    assert_equal 1, M.percent_of(1000, 0.1)
    assert_equal 29, M.percent_of(1000, 2.9)
    assert_kind_of Integer, M.percent_of(1000, 2.9)
  end

  def test_round_to_half_unit
    assert_equal 8700, M.round_to_half_unit(8723)
    assert_equal 8750, M.round_to_half_unit(8725)
    assert_equal 8750, M.round_to_half_unit(8774)
    assert_equal 8800, M.round_to_half_unit(8775)
    assert_equal 0, M.round_to_half_unit(24)
    assert_equal 50, M.round_to_half_unit(25)
    assert_equal 100, M.round_to_half_unit(100)
  end

  def test_allocate_sums_exactly
    assert_equal [34, 33, 33], M.allocate(100, [1, 1, 1])
    assert_equal [2500, 7500], M.allocate(10_000, [1, 3])
    assert_equal [1, 0, 0], M.allocate(1, [1, 1, 1])
    assert_equal [0, 100], M.allocate(100, [0, 5])
    assert_equal [], M.allocate(100, [])
    assert_equal [50, 50], M.allocate(100, [0, 0])
    parts = M.allocate(99_999, [199_900, 49_900, 1])
    assert_equal 99_999, parts.sum
  end

  def test_to_decimal_string
    assert_equal "6486.40", M.to_decimal_string(648_640)
    assert_equal "0.05", M.to_decimal_string(5)
    assert_equal "0.00", M.to_decimal_string(0)
    assert_equal "-1.50", M.to_decimal_string(-150)
  end

  def test_clamp_non_negative
    assert_equal 0, M.clamp_non_negative(-5)
    assert_equal 7, M.clamp_non_negative(7)
  end

  def test_format
    huf = { "template" => "{{amount}} Ft", "decimals" => 0, "thousands" => " ", "decimal" => "," }
    assert_equal "6 486 Ft", M.format(648_640, huf)
    assert_equal "6 487 Ft", M.format(648_650, huf)
    usd = { "template" => "${{amount}}", "decimals" => 2, "thousands" => ",", "decimal" => "." }
    assert_equal "$1,234,567.89", M.format(123_456_789, usd)
    assert_equal "$0.05", M.format(5, usd)
    eur = { "template" => "{{amount}} €", "decimals" => 2, "thousands" => ".", "decimal" => "," }
    assert_equal "1.234,50 €", M.format(123_450, eur)
    assert_equal "12.50", M.format(1250, nil)
  end
end
