# frozen_string_literal: true

require "test_helper"

class CodForm::OtpServicePhoneFirstTest < ActiveSupport::TestCase
  PHONE_FIRST = { "steps" => { "phone_first" => true } }.freeze
  ADDRESS_FIRST = { "steps" => { "phone_first" => false } }.freeze
  OTP_ON = { "otp" => { "enabled" => true } }.freeze
  OTP_OFF = { "otp" => { "enabled" => false } }.freeze

  test "phone-first does not turn OTP on when the parent switch is off" do
    assert_equal false, CodForm::OtpService.enabled_for?(nil, PHONE_FIRST, OTP_OFF)
    assert_equal false, CodForm::OtpService.enabled_for?(nil, PHONE_FIRST, {})
    assert_equal false, CodForm::OtpService.phone_first?(PHONE_FIRST, OTP_OFF)
  end

  test "phone-first is honoured when the parent switch is on" do
    assert_equal true, CodForm::OtpService.enabled_for?(nil, PHONE_FIRST, OTP_ON)
    assert_equal true, CodForm::OtpService.phone_first?(PHONE_FIRST, OTP_ON)
  end

  test "address-first form with OTP on is not phone-first" do
    assert_equal true, CodForm::OtpService.enabled_for?(nil, ADDRESS_FIRST, OTP_ON)
    assert_equal false, CodForm::OtpService.phone_first?(ADDRESS_FIRST, OTP_ON)
  end
end
