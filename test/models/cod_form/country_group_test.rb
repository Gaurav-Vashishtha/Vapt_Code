# frozen_string_literal: true

require "test_helper"

class CodForm::CountryGroupTest < ActiveSupport::TestCase
  test "country codes are upper-cased and de-duplicated" do
    group = CodForm::CountryGroup.create!(name: "Test group", country_codes: ["zz", " ZZ ", "yy"], position: 50)
    assert_equal %w[ZZ YY], group.country_codes
    assert group.include_country?("zz")
  end

  test "country_codes must be an array of ISO2 codes" do
    assert CodForm::CountryGroup.new(name: "Bad", country_codes: "HU,CO").invalid?
    assert CodForm::CountryGroup.new(name: "Bad", country_codes: ["HUN"]).invalid?
  end

  test "for_country returns active groups in position order" do
    late = CodForm::CountryGroup.create!(name: "Late", country_codes: ["ZZ"], position: 90)
    early = CodForm::CountryGroup.create!(name: "Early", country_codes: ["ZZ"], position: 80)
    CodForm::CountryGroup.create!(name: "Inactive", country_codes: ["ZZ"], position: 70, active: false)

    assert_equal [early.id, late.id], CodForm::CountryGroup.for_country("zz").pluck(:id)
    assert_empty CodForm::CountryGroup.for_country(nil)
  end
end
