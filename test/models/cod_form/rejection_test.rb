# frozen_string_literal: true

require "test_helper"

class CodForm::RejectionTest < ActiveSupport::TestCase
  test "stores a rejection without updated_at" do
    rejection = CodForm::Rejection.create!(shop: shops(:regular_shop), reason_code: "phone_blocked",
                                           stage: "order", subject_kind: "phone", subject_masked: "+36•••••4521")

    assert_not_nil rejection.created_at
    assert_not CodForm::Rejection.column_names.include?("updated_at")
    assert_equal({}, rejection.detail)
  end

  test "validates stage and subject kind" do
    shop = shops(:regular_shop)
    assert CodForm::Rejection.new(shop: shop, reason_code: "x", stage: "checkout").invalid?
    assert CodForm::Rejection.new(shop: shop, reason_code: "x", stage: "quote", subject_kind: "name").invalid?
    assert CodForm::Rejection.new(shop: shop, stage: "quote").invalid?
  end
end
