# frozen_string_literal: true

require_relative "../support/plain_boot"
require_relative "../../../../app/services/cod_form/integrations/event_payloads"

class CodFormIntegrationEventPayloadsTest < Minitest::Test
  EP = CodForm::Integrations::EventPayloads

  SESSION = {
    "order_id" => "6123456789", "order_name" => "#1042", "order_total_cents" => 648_640, "currency" => "HUF",
    "country_code" => "HU",
    "contact" => { "phone_e164" => "+36 30 123 4567", "email" => "anna@example.com", "first_name" => "Anna", "last_name" => "Kiss" },
    "address" => { "city" => "Budapest", "province" => "BU", "zip" => "1051", "country" => "HU" },
    "attribution" => { "utm_campaign" => "autumn" },
    "quote_snapshot" => {
      "currency" => "HUF", "total_cents" => 648_640, "subtotal_cents" => 599_700, "shipping_cents" => 149_000,
      "cod_fee" => { "amount_cents" => 50_000 },
      "lines" => [{ "variant_id" => "44111", "product_id" => "8111", "title" => "Widget", "quantity" => 3,
                    "unit_price_cents" => 199_900, "image" => "https://cdn/x.png" }]
    }
  }.freeze

  def profile
    EP.profile_from_session(SESSION)
  end

  def test_event_names
    assert_equal "COD Form Order Placed", EP::EVENT_ORDER
    assert_equal "COD Form Abandoned", EP::EVENT_ABANDONED
  end

  def test_klaviyo_order_event
    body = EP.klaviyo(event: EP::EVENT_ORDER, profile: profile, properties: EP.order_properties(SESSION),
                      time: Time.utc(2026, 10, 3, 9, 58, 1), value_cents: 648_640, currency: "HUF",
                      unique_id: "order_6123456789")
    data = body["data"]
    assert_equal "event", data["type"]
    attrs = data["attributes"]
    assert_equal({ "data" => { "type" => "metric", "attributes" => { "name" => "COD Form Order Placed" } } }, attrs["metric"])
    profile_attrs = attrs["profile"]["data"]["attributes"]
    assert_equal "profile", attrs["profile"]["data"]["type"]
    assert_equal "anna@example.com", profile_attrs["email"]
    assert_equal "+36301234567", profile_attrs["phone_number"]
    assert_equal "Anna", profile_attrs["first_name"]
    assert_equal({ "city" => "Budapest", "region" => "BU", "zip" => "1051", "country" => "HU" }, profile_attrs["location"])
    assert_equal "2026-10-03T09:58:01Z", attrs["time"]
    assert_in_delta 6486.40, attrs["value"]
    assert_equal "HUF", attrs["value_currency"]
    assert_equal "order_6123456789", attrs["unique_id"]
    assert_equal "#1042", attrs["properties"]["order_name"]
    assert_equal 3, attrs["properties"]["item_count"]
    assert_equal "cod", attrs["properties"]["payment_method"]
  end

  def test_klaviyo_needs_an_identifier
    assert_nil EP.klaviyo(event: "x", profile: { "first_name" => "Anna" }, properties: {})
    phone_only = EP.klaviyo(event: "x", profile: { "phone_e164" => "+36301234567" }, properties: {})
    assert_equal({ "phone_number" => "+36301234567" }, phone_only["data"]["attributes"]["profile"]["data"]["attributes"])
    refute phone_only["data"]["attributes"].key?("value")
  end

  def test_klaviyo_abandoned_event_carries_the_recovery_link
    props = EP.abandoned_properties(SESSION, recovery_url: "https://brand.hu/?codk_recover=tok")
    assert_equal "https://brand.hu/?codk_recover=tok", props["recovery_url"]
    assert_in_delta 6486.40, props["total"]
    assert_equal "Widget", props["items"].first["title"]
    refute props.key?("order_id")
  end

  def test_omnisend_event
    body = EP.omnisend(event: EP::EVENT_ABANDONED, profile: profile,
                       properties: EP.abandoned_properties(SESSION, recovery_url: "https://brand.hu/?codk_recover=tok"),
                       time: Time.utc(2026, 10, 3, 9, 58, 1), event_id: "codf_abc")
    assert_equal "COD Form Abandoned", body["eventName"]
    assert_equal "api", body["origin"]
    assert_equal "anna@example.com", body["contact"]["email"]
    assert_equal "+36301234567", body["contact"]["phone"]
    assert_equal "Anna", body["contact"]["firstName"]
    assert_equal "1051", body["contact"]["postalCode"]
    assert_equal "2026-10-03T09:58:01Z", body["eventTime"]
    assert_equal "codf_abc", body["eventID"]
    assert_equal "https://brand.hu/?codk_recover=tok", body["properties"]["recovery_url"]
  end

  def test_omnisend_needs_an_identifier
    assert_nil EP.omnisend(event: "x", profile: {}, properties: {})
  end

  def test_order_properties_money_is_decimal
    props = EP.order_properties(SESSION)
    assert_in_delta 6486.40, props["total"]
    assert_in_delta 1490.0, props["shipping"]
    assert_in_delta 500.0, props["cod_fee"]
    assert_in_delta 1999.0, props["items"].first["price"]
    assert_equal "autumn", props["utm_campaign"]
    refute props.key?("discount_code")
  end

  def test_bad_phone_is_dropped
    assert_nil EP.e164("12345")
    assert_equal "+36301234567", EP.e164("0036301234567")
  end
end
