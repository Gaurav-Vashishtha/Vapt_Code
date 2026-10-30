# frozen_string_literal: true

# Plain minitest, no Rails:  ruby test/services/cod_form/money_format_adapter_test.rb
require "minitest/autorun"
require_relative "../../../app/services/cod_form/adapters/money_format_adapter"

class CodFormMoneyFormatAdapterTest < Minitest::Test
  A = CodForm::MoneyFormatAdapter

  def test_plain_amount
    assert_equal({ "template" => "Rs. {{amount}}", "decimals" => 2, "thousands" => ",", "decimal" => "." }, A.parse("Rs. {{amount}}"))
  end

  def test_no_decimals_with_space_separator
    assert_equal({ "template" => "{{amount}} Ft", "decimals" => 0, "thousands" => " ", "decimal" => "," },
                 A.parse("{{amount_no_decimals_with_space_separator}} Ft"))
  end

  def test_comma_separator
    assert_equal({ "template" => "€{{amount}}", "decimals" => 2, "thousands" => ".", "decimal" => "," },
                 A.parse("€{{amount_with_comma_separator}}"))
    assert_equal 0, A.parse("${{amount_no_decimals_with_comma_separator}}")["decimals"]
  end

  def test_apostrophe_and_spaces_inside_braces
    parsed = A.parse("CHF {{ amount_with_apostrophe_separator }}")
    assert_equal "CHF {{amount}}", parsed["template"]
    assert_equal "'", parsed["thousands"]
  end

  def test_html_is_stripped
    assert_equal "{{amount}} MAD", A.parse('<span class="money">{{amount}} MAD</span>')["template"]
  end

  def test_unknown_token_falls_back_to_amount_rules
    assert_equal 2, A.parse("{{amount_something_new}} X")["decimals"]
  end

  def test_missing_placeholder_gives_a_generic_format
    assert_equal({ "template" => "{{amount}} HUF", "decimals" => 0, "thousands" => ",", "decimal" => "." }, A.parse("", currency: "huf"))
    assert_equal "{{amount}}", A.parse(nil)["template"]
    assert_equal 2, A.generic("EUR")["decimals"]
  end
end
