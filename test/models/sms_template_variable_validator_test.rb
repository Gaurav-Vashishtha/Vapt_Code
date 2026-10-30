require "test_helper"

class SmsTemplateVariableValidatorTest < ActiveSupport::TestCase
  test "returns errors for disallowed variables and limit overflow" do
    config = SmsTemplateTypeConfig.new(
      key: "order_confirmation",
      display_name: "Order Confirmation",
      target_column: "order_confirmation_template",
      allowed_variables: %w[name number],
      max_variables: 1
    )

    result = SmsTemplateVariableValidator.call(
      body: "Hi {{name}} {{number}} {{bad_var}}",
      type_config: config
    )

    assert_not result.ok?
    assert_includes result.errors.join(","), "Unsupported variables"
    assert_includes result.errors.join(","), "exceeds allowed limit"
  end

  test "passes when all variables are allowed under limit" do
    config = SmsTemplateTypeConfig.new(
      key: "retry_otp",
      display_name: "Retry OTP",
      target_column: "retry_template",
      allowed_variables: %w[otp link],
      max_variables: 3
    )

    result = SmsTemplateVariableValidator.call(
      body: "Use {{otp}} and {{link}}",
      type_config: config
    )

    assert result.ok?
    assert_equal %w[otp link], result.variables
  end
end
