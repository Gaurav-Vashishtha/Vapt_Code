# frozen_string_literal: true

require "test_helper"

class CodForm::AbTestTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
    @variants = [{ "key" => "a", "offer_id" => nil, "weight" => 50 }, { "key" => "control", "offer_id" => nil, "weight" => 50 }]
  end

  test "valid with two variants whose weights sum to 100" do
    assert CodForm::AbTest.new(shop: @shop, name: "T", offer_type: "bump", variants: @variants).valid?
  end

  test "rejects one variant, duplicate keys and wrong weight sums" do
    test_record = CodForm::AbTest.new(shop: @shop, name: "T", offer_type: "bump")

    test_record.variants = [@variants.first]
    assert_not test_record.valid?

    test_record.variants = [@variants.first, @variants.first]
    assert_not test_record.valid?

    test_record.variants = [@variants.first, @variants.last.merge("weight" => 40)]
    assert_not test_record.valid?
  end

  test "variants are immutable once started" do
    test_record = CodForm::AbTest.create!(shop: @shop, name: "T", offer_type: "bump", variants: @variants)
    test_record.start!
    assert test_record.running?

    test_record.variants = [@variants.first.merge("weight" => 60), @variants.last.merge("weight" => 40)]
    assert_not test_record.valid?
  end
end
