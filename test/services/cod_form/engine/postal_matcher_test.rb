# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEnginePostalMatcherTest < Minitest::Test
  include EngineTestHelper
  P = CodForm::Engine::PostalMatcher

  def test_parse_fixture_cases
    fixture("postal_cases")["parse"].each do |c|
      assert_equal c["expected"], P.parse(c["list"]), "parse #{c['list'].inspect}"
    end
  end

  def test_match_fixture_cases
    fixture("postal_cases")["match"].each do |c|
      assert_equal c["expected"], P.match?(c["code"], P.parse(c["list"])), "#{c['code'].inspect} in #{c['list'].inspect}"
    end
  end

  def test_match_accepts_a_raw_list
    assert P.match?("4000 12", "110001, 4000*")
    refute P.match?("5000", "110001, 4000*")
  end

  def test_normalize
    assert_equal "SW1A1AA", P.normalize(" sw1a-1aa ")
    assert_equal "", P.normalize(nil)
  end

  def test_parse_nil_and_empty
    assert_equal [], P.parse(nil)
    assert_equal [], P.parse("")
    assert_equal [], P.parse([])
  end
end
