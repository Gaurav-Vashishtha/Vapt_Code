# frozen_string_literal: true

require "test_helper"

class CodForm::IntegrationTest < ActiveSupport::TestCase
  setup do
    @shop = shops(:regular_shop)
  end

  test "for creates one disconnected row per shop and provider" do
    integration = CodForm::Integration.for(@shop, :klaviyo)

    assert_equal "disconnected", integration.status
    assert_equal integration.id, CodForm::Integration.for(@shop, "klaviyo").id
    assert CodForm::Integration.new(shop: @shop, provider: "mailchimp").invalid?
  end

  test "credentials are never serialised or inspected" do
    integration = CodForm::Integration.for(@shop, :klaviyo)
    integration.update!(credentials: { "private_api_key" => "pk_secret_123" })

    assert_not integration.as_json.key?("credentials")
    assert_not_includes integration.to_json, "pk_secret_123"
    assert_not_includes integration.inspect, "pk_secret_123"
  end

  test "status helpers" do
    integration = CodForm::Integration.for(@shop, :google_sheets)

    integration.mark_success!
    assert integration.connected?
    assert_not_nil integration.last_success_at

    integration.mark_error!("quota exceeded")
    assert_equal "error", integration.status

    integration.disconnect!
    assert_equal({}, integration.credentials)
    assert_equal "disconnected", integration.status
  end
end
