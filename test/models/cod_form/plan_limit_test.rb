# frozen_string_literal: true

require "test_helper"

class CodForm::PlanLimitTest < ActiveSupport::TestCase
  test "plan rows need a known tier as scope_key" do
    assert CodForm::PlanLimit.new(scope_type: "plan", scope_key: "starter").invalid?
  end

  test "uniqueness also holds for a null plan_tier" do
    CodForm::PlanLimit.where(scope_type: "shop", scope_key: "42").delete_all
    CodForm::PlanLimit.create!(scope_type: "shop", scope_key: "42", monthly_cap: 100)

    assert CodForm::PlanLimit.new(scope_type: "shop", scope_key: "42").invalid?
  end

  test "plan_tier is only allowed on country_group rows" do
    assert CodForm::PlanLimit.new(scope_type: "shop", scope_key: "43", plan_tier: "pro").invalid?
    assert CodForm::PlanLimit.new(scope_type: "country_group", scope_key: "999", plan_tier: "pro").valid?
  end

  test "blank form values become nil; a nil cap is unlimited" do
    limit = CodForm::PlanLimit.new(scope_type: "shop", scope_key: "44", plan_tier: "", at_cap_behaviour: "")

    assert limit.valid?
    assert_nil limit.plan_tier
    assert_nil limit.at_cap_behaviour
    assert limit.unlimited?
  end

  test "rejects unknown behaviours and negative numbers" do
    assert CodForm::PlanLimit.new(scope_type: "shop", scope_key: "45", at_cap_behaviour: "block").invalid?
    assert CodForm::PlanLimit.new(scope_type: "shop", scope_key: "45", monthly_cap: -1).invalid?
    assert CodForm::PlanLimit.new(scope_type: "shop", scope_key: "45", overage_rate: -0.05).invalid?
  end
end
