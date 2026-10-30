# frozen_string_literal: true

require "test_helper"

class CodForm::GlobalSettingTest < ActiveSupport::TestCase
  test "current returns the singleton with the documented defaults" do
    CodForm::GlobalSetting.delete_all
    CodForm::GlobalSetting.expire_cache

    setting = CodForm::GlobalSetting.current

    assert setting.persisted?
    assert_equal false, setting.kill_switch
    assert_equal false, setting.module_default_on
    assert_equal "fallback", setting.at_cap_behaviour
    assert_equal 0, setting.grace_orders
    assert_equal [80, 100], setting.usage_notice_thresholds
    assert_equal({}, setting.rate_limits)
    assert_equal setting.id, CodForm::GlobalSetting.current.id
    assert_equal 1, CodForm::GlobalSetting.count
  end

  test "a second row is refused" do
    CodForm::GlobalSetting.current
    assert CodForm::GlobalSetting.new.invalid?
  end

  test "validates behaviour and thresholds" do
    setting = CodForm::GlobalSetting.current

    setting.at_cap_behaviour = "stop"
    assert setting.invalid?

    setting.at_cap_behaviour = "grace"
    setting.usage_notice_thresholds = "80,100"
    assert setting.invalid?

    setting.usage_notice_thresholds = [50, 80, 100]
    assert setting.valid?
  end
end
