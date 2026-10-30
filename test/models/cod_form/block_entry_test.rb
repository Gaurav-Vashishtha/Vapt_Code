# frozen_string_literal: true

require "test_helper"

class CodForm::BlockEntryTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  test "normalize" do
    assert_equal "36301234567", CodForm::BlockEntry.normalize("phone", "+36 30 123 4567")
    assert_equal "301234567", CodForm::BlockEntry.normalize(:phone, "030-123-4567")
    assert_equal "a@b.com", CodForm::BlockEntry.normalize("email", "  A@B.com ")
    assert_equal "*@x.com", CodForm::BlockEntry.normalize("email", "*@X.com")
    assert_equal "10.0.0.0/8", CodForm::BlockEntry.normalize("ip", " 10.0.0.0/8 ")
  end

  test "value_normalized is set before validation and is unique per shop and kind" do
    entry = CodForm::BlockEntry.create!(shop: @shop, kind: "phone", value: "+36 30 123 4567")
    assert_equal "36301234567", entry.value_normalized

    duplicate = CodForm::BlockEntry.new(shop: @shop, kind: "phone", value: "36301234567")
    assert_not duplicate.valid?
  end

  test "validates the value by kind" do
    assert_not CodForm::BlockEntry.new(shop: @shop, kind: "phone", value: "abc").valid?
    assert_not CodForm::BlockEntry.new(shop: @shop, kind: "email", value: "not-an-email").valid?
    assert_not CodForm::BlockEntry.new(shop: @shop, kind: "ip", value: "999.1.1.1").valid?
    assert_not CodForm::BlockEntry.new(shop: @shop, kind: "zip", value: "1051").valid?

    assert CodForm::BlockEntry.new(shop: @shop, kind: "email", value: "*@spam.com").valid?
    assert CodForm::BlockEntry.new(shop: @shop, kind: "ip", value: "10.0.0.0/8").valid?
  end
end
