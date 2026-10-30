# frozen_string_literal: true

require_relative "engine_test_helper"
require "tmpdir"

class CodFormEnginePhoneTest < Minitest::Test
  include EngineTestHelper
  P = CodForm::Engine::Phone
  C = CodForm::Engine::CountrySchema

  def test_fixture_cases
    fixture("phone_cases").each do |c|
      result = P.validate(raw: c["raw"], country: c["country"], rules: C.phone_rules(country: c["country"], data: countries))
      label = "#{c['country']} #{c['raw'].inspect}"
      assert_equal c["valid"], result["valid"], label
      if c["error"].nil?
        assert_nil result["error"], label
      else
        assert_equal c["error"], result["error"], label
      end
      %w[national e164 digits].each { |key| assert_equal c[key], result[key], "#{label} #{key}" if c.key?(key) }
    end
  end

  def test_accepts_the_whole_country_schema_as_rules
    result = P.validate(raw: "06 30 123 4567", country: "HU", rules: C.for(country: "HU", data: countries))
    assert_equal "+36301234567", result["e164"]
  end

  def test_result_shape
    result = P.validate(raw: "301234567", country: "HU", rules: C.phone_rules(country: "HU", data: countries))
    assert_equal %w[valid national e164 digits error], result.keys
  end
end

class CodFormEngineCountrySchemaTest < Minitest::Test
  include EngineTestHelper
  C = CodForm::Engine::CountrySchema
  REQUIRED = %w[IN PK MA CO PE DO HU RS AE SA EG ID PH MX TR RO PL ES IT PT FR DE GB US].freeze

  def test_file_has_every_required_country_and_a_default
    REQUIRED.each { |code| assert countries.key?(code), "missing #{code}" }
    assert countries.key?("default")
    assert_equal REQUIRED.sort, C.countries(data: countries)
  end

  def test_every_entry_is_complete_and_consistent
    countries.each do |code, entry|
      next if code == "default"

      assert_match(/\A\d{1,3}\z/, entry["dial_code"], code)
      phone = entry["phone"]
      assert_operator phone["min"], :<=, phone["max"], code
      assert_includes [true, false], phone["strip_leading_zero"], code
      assert_kind_of Array, phone["mobile_prefixes"], code
      address = entry["address"]
      assert_includes %w[hidden select auto], address["province"]["mode"], code
      assert_includes [true, false], address["zip"]["required"], code
      assert Regexp.new(address["zip"]["regex"]), code
      assert_includes %w[label_zip label_pincode], address["zip"]["label_key"], code
    end
  end

  def test_postal_patterns
    zip = ->(code) { Regexp.new(C.for(country: code, data: countries)["address"]["zip"]["regex"]) }
    assert_match zip.call("HU"), "1051"
    refute_match zip.call("HU"), "10510"
    assert_match zip.call("IN"), "411001"
    refute_match zip.call("IN"), "011001"
    assert_match zip.call("GB"), "SW1A 1AA"
    assert_match zip.call("GB"), "m11ae"
    refute_match zip.call("GB"), "12345"
    assert_match zip.call("PL"), "00-950"
    assert_match zip.call("US"), "94107-1234"
  end

  def test_merges_the_default_entry
    hu = C.for(country: "hu", data: countries)
    assert_equal ["HU", "36", "hidden", true], [hu["country"], hu["dial_code"], hu["address"]["province"]["mode"], hu["known"]]
    assert_equal "free", hu["address"]["city"]["mode"]
    unknown = C.for(country: "ZZ", data: countries)
    assert_equal ["", 6, 14, false, false], [unknown["dial_code"], unknown["phone"]["min"], unknown["phone"]["max"], unknown["address"]["zip"]["required"], unknown["known"]]
    partial = C.for(country: "XX", data: { "XX" => { "dial_code" => "999" } })
    assert_equal ["999", 6, "auto"], [partial["dial_code"], partial["phone"]["min"], partial["address"]["province"]["mode"]]
  end

  def test_load_uses_an_injectable_path
    path = File.join(Dir.mktmpdir, "countries.json")
    File.write(path, JSON.generate("default" => { "dial_code" => "" }, "AA" => { "dial_code" => "7" }))
    assert_equal "7", C.for(country: "AA", data: C.load(path))["dial_code"]
    assert_equal "36", C.for(country: "HU")["dial_code"], "default path"
  end
end
