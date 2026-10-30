require "test_helper"

class SmsTemplateApprovalServiceTest < ActiveSupport::TestCase
  setup do
    @shop = Shop.create!(shopify_domain: "template-test.myshopify.com", shopify_token: "token")
    @setting = Setting.create!(shop: @shop)
    @config = SmsTemplateTypeConfig.create!(
      key: "order_confirmation",
      display_name: "Order Confirmation",
      target_column: "order_confirmation_template",
      allowed_variables: %w[name number link],
      max_variables: 3,
      active: true
    )
  end

  test "submit creates pending approval when valid" do
    result = SmsTemplateApprovalService.submit(
      shop: @shop,
      template_type_key: @config.key,
      body: "Hi {{name}}, order {{number}}",
      submitted_by: "owner@test.com"
    )

    assert result.ok?
    assert_equal SmsTemplateApproval::STATUSES[:pending], result.record.status
    assert_equal @setting.id, result.record.setting_id
  end

  test "submit fails when variable is not allowed" do
    result = SmsTemplateApprovalService.submit(
      shop: @shop,
      template_type_key: @config.key,
      body: "Hi {{name}} {{bad_var}}",
      submitted_by: "owner@test.com"
    )

    assert_not result.ok?
    assert_includes result.errors.join(","), "Unsupported variables"
  end
end
