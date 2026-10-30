# frozen_string_literal: true

require "test_helper"

class Whatsapp::AutoApprovalPolicyTest < ActiveSupport::TestCase
  FakeShop = Struct.new(:country_code, :shop_created_date, :customer_count, :shopify_domain)

  def with_countries(value)
    old = ENV["WHATSAPP_AUTO_APPROVE_COUNTRIES"]
    value.nil? ? ENV.delete("WHATSAPP_AUTO_APPROVE_COUNTRIES") : ENV["WHATSAPP_AUTO_APPROVE_COUNTRIES"] = value
    yield
  ensure
    old.nil? ? ENV.delete("WHATSAPP_AUTO_APPROVE_COUNTRIES") : ENV["WHATSAPP_AUTO_APPROVE_COUNTRIES"] = old
  end

  test "Egyptian stores are approved regardless of age and size" do
    with_countries(nil) do
      policy = Whatsapp::AutoApprovalPolicy.new(FakeShop.new("eg", 1.day.ago.to_s, 0, "x.myshopify.com"))
      assert policy.eligible?
      assert_includes policy.note, "EG"
    end
  end

  test "fast-track countries can be changed or switched off" do
    with_countries("PK, MA") do
      assert Whatsapp::AutoApprovalPolicy.new(FakeShop.new("PK", nil, 0, "x")).eligible?
    end
    with_countries("none") do
      assert_empty Whatsapp::AutoApprovalPolicy.auto_approve_countries
    end
  end
end
