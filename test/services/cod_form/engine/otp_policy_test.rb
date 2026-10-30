# frozen_string_literal: true

require_relative "engine_test_helper"

class CodFormEngineOtpPolicyTest < Minitest::Test
  O = CodForm::Engine::OtpPolicy

  def required?(overrides = {})
    O.required?(**{ shop_enabled: true, mode: "before_order", risk_band: nil, target_band: "medium", verified: false }.merge(overrides))
  end

  def test_before_order
    assert required?
    refute required?(verified: true)
    refute required?(shop_enabled: false)
    assert required?(mode: nil), "default mode"
  end

  def test_order_first_never_blocks_the_order
    refute required?(mode: "order_first")
  end

  def test_risk_based
    refute required?(mode: "risk_based", risk_band: "low")
    assert required?(mode: "risk_based", risk_band: "medium")
    assert required?(mode: "risk_based", risk_band: "high")
    refute required?(mode: "risk_based", risk_band: nil)
    refute required?(mode: "risk_based", risk_band: "medium", target_band: "high")
    assert required?(mode: "risk_based", risk_band: "medium", target_band: nil)
    refute required?(mode: "risk_based", risk_band: "high", verified: true)
    refute required?(mode: "risk_based", risk_band: "high", shop_enabled: false)
  end
end
