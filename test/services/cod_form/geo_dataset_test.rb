# frozen_string_literal: true

# Plain minitest, no Rails:  ruby test/services/cod_form/geo_dataset_test.rb
require "minitest/autorun"
require "json"

class CodFormGeoDatasetTest < Minitest::Test
  DIR = File.expand_path("../../../lib/cod_form/geo", __dir__)
  REQUIRED = %w[PK MA CO PE DO HU RS IN].freeze
  EXPECTED_PROVINCES = { "IN" => 37, "CO" => 33, "PE" => 26, "PK" => 7, "MA" => 12, "DO" => 32, "HU" => 20, "RS" => 25 }.freeze

  def dataset(code)
    JSON.parse(File.read(File.join(DIR, "#{code}.json"), encoding: "UTF-8"))
  end

  def test_every_launch_market_and_india_has_a_file
    REQUIRED.each { |code| assert File.exist?(File.join(DIR, "#{code}.json")), code }
  end

  def test_shape
    REQUIRED.each do |code|
      data = dataset(code)
      assert_equal code, data["country"]
      assert_includes [true, false], data["shopify_provinces"], code
      assert_equal EXPECTED_PROVINCES[code], data["provinces"].size, code
      data["provinces"].each do |province|
        assert_equal %w[code name], province.keys.sort, code
        refute_empty province["code"].to_s
        refute_empty province["name"].to_s
      end
      assert_equal "by_province", data.dig("cities", "mode"), code
      assert_kind_of Array, data.dig("cities", "list")
    end
  end

  def test_province_codes_and_names_are_unique
    REQUIRED.each do |code|
      provinces = dataset(code)["provinces"]
      assert_equal provinces.size, provinces.map { |p| p["code"] }.uniq.size, code
      assert_equal provinces.size, provinces.map { |p| p["name"] }.uniq.size, code
    end
  end

  def test_every_province_has_at_least_one_city_and_no_unknown_province_key
    REQUIRED.each do |code|
      data = dataset(code)
      codes = data["provinces"].map { |p| p["code"] }
      by_province = data.dig("cities", "by_province")
      assert_equal codes.sort, by_province.keys.sort, code
      by_province.each do |province, cities|
        refute_empty cities, "#{code}-#{province}"
        assert_equal cities.size, cities.uniq.size, "#{code}-#{province}"
        cities.each { |city| assert_equal city, city.strip }
      end
    end
  end

  def test_codes_fit_the_postal_route_and_rate_conditions
    # Shipping-rate conditions store "<country>-<province code>" (C.3).
    REQUIRED.each do |code|
      dataset(code)["provinces"].each { |p| assert_match(/\A[A-Z0-9\-]{1,8}\z/, p["code"], code) }
    end
  end

  def test_shopify_province_flag
    assert_equal %w[CO IN PE], REQUIRED.select { |code| dataset(code)["shopify_provinces"] }.sort
  end

  def test_known_codes
    assert_equal "Maharashtra", dataset("IN")["provinces"].find { |p| p["code"] == "MH" }["name"]
    assert_equal "Bogotá, D.C.", dataset("CO")["provinces"].find { |p| p["code"] == "DC" }["name"]
    assert_includes dataset("PK").dig("cities", "by_province", "PB"), "Lahore"
    assert_includes dataset("HU").dig("cities", "by_province", "BU"), "Budapest"
  end
end
