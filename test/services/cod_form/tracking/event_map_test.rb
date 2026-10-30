# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../../app/services/cod_form/tracking/event_map"

class CodFormEventMapTest < Minitest::Test
  EM = CodForm::Tracking::EventMap

  def test_form_open_names_per_platform
    expected = {
      "meta" => "InitiateCheckout", "tiktok" => "InitiateCheckout", "ga4" => "begin_checkout",
      "snapchat" => "START_CHECKOUT", "pinterest" => "add_to_cart", "google_ads" => nil
    }
    expected.each do |platform, name|
      assert_nil_or_equal name, EM.event_name(platform: platform, moment: "initiate_checkout")
    end
  end

  def test_purchase_names_per_platform
    expected = {
      "meta" => "Purchase", "tiktok" => "CompletePayment", "ga4" => "purchase",
      "snapchat" => "PURCHASE", "pinterest" => "checkout", "google_ads" => "conversion"
    }
    expected.each do |platform, name|
      assert_equal name, EM.event_name(platform: platform, moment: "purchase", config: { "purchase_event" => "purchase" })
    end
  end

  def test_lead_in_place_of_purchase
    config = { "purchase_event" => "lead" }
    assert_equal "Lead", EM.event_name(platform: "meta", moment: "purchase", config: config)
    assert_equal "SubmitForm", EM.event_name(platform: "tiktok", moment: "purchase", config: config)
    assert_equal "generate_lead", EM.event_name(platform: "ga4", moment: "purchase", config: config)
    assert_equal "SIGN_UP", EM.event_name(platform: "snapchat", moment: "purchase", config: config)
    assert_equal "lead", EM.event_name(platform: "pinterest", moment: "purchase", config: config)
  end

  def test_lead_setting_does_not_change_form_open
    assert_equal "InitiateCheckout",
                 EM.event_name(platform: "meta", moment: "initiate_checkout", config: { "purchase_event" => "lead" })
  end

  def test_tiktok_place_order_option
    assert_equal "PlaceAnOrder",
                 EM.event_name(platform: "tiktok", moment: "purchase", config: { "tiktok_event" => "place_order" })
    assert_equal "SubmitForm",
                 EM.event_name(platform: "tiktok", moment: "purchase",
                               config: { "tiktok_event" => "place_order", "purchase_event" => "lead" })
  end

  def test_browser_name_differs_only_for_pinterest_add_to_cart
    assert_equal "addtocart", EM.browser_event_name(platform: "pinterest", moment: "initiate_checkout")
    assert_equal "checkout", EM.browser_event_name(platform: "pinterest", moment: "purchase")
    assert_equal "Purchase", EM.browser_event_name(platform: "meta", moment: "purchase")
  end

  def test_unknown_moment_and_platform
    assert_nil EM.event_name(platform: "meta", moment: "refund")
    assert_nil EM.event_name(platform: "myspace", moment: "purchase")
    refute EM.moment?("refund")
    assert EM.moment?("purchase")
  end

  def test_event_ids_are_shared_and_deterministic
    assert_equal "codkf_0b6c9c2e-1111_ic", EM.event_id(moment: "initiate_checkout", session_id: "0b6c9c2e-1111")
    assert_equal "order_6123456789_purchase", EM.event_id(moment: "purchase", order_id: "6123456789")
    assert_equal "order_6123456789_lead", EM.event_id(moment: "purchase", order_id: 6_123_456_789, purchase_event: "lead")
  end

  def test_event_id_needs_its_subject
    assert_nil EM.event_id(moment: "initiate_checkout", session_id: "")
    assert_nil EM.event_id(moment: "purchase", order_id: nil)
    assert_nil EM.event_id(moment: "other", session_id: "x", order_id: "1")
  end

  def test_moment_enabled_follows_config_events
    assert EM.moment_enabled?({}, "purchase")
    assert EM.moment_enabled?({ "events" => { "form_open" => true } }, "initiate_checkout")
    refute EM.moment_enabled?({ "events" => { "form_open" => false } }, "initiate_checkout")
    refute EM.moment_enabled?({ "events" => { "purchase" => false } }, "purchase")
    refute EM.moment_enabled?({}, "add_payment_info")
  end

  def test_browser_dedup_fields
    assert_equal "eventID", EM.browser_dedup_field("meta")
    assert_equal "client_dedup_id", EM.browser_dedup_field("snapchat")
    assert_equal "transaction_id", EM.browser_dedup_field("ga4")
  end

  private

  def assert_nil_or_equal(expected, actual)
    expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
  end
end
