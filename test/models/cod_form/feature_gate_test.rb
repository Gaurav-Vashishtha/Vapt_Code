# frozen_string_literal: true

require "test_helper"

class CodForm::FeatureGateTest < ActiveSupport::TestCase
  test "defaults to free and enabled" do
    gate = CodForm::FeatureGate.new(feature_key: "ws1_test_gate")

    assert gate.valid?
    assert_equal "free", gate.min_tier
    assert_equal true, gate.enabled
  end

  test "feature_key is unique and snake_case, min_tier is a known tier" do
    CodForm::FeatureGate.create!(feature_key: "ws1_test_gate")

    assert CodForm::FeatureGate.new(feature_key: "ws1_test_gate").invalid?
    assert CodForm::FeatureGate.new(feature_key: "Bad Key").invalid?
    assert CodForm::FeatureGate.new(feature_key: "ws1_other_gate", min_tier: "gold").invalid?
  end
end
