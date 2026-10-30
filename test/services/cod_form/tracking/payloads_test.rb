# frozen_string_literal: true

require_relative "../support/plain_boot"
require "digest"
require "json"
require_relative "../../../../app/services/cod_form/tracking/event_builder"
require_relative "../../../../app/services/cod_form/tracking/payloads"

class CodFormTrackingPayloadsTest < Minitest::Test
  P = CodForm::Tracking::Payloads
  EB = CodForm::Tracking::EventBuilder
  NOW = 1_790_000_000

  def session(overrides = {})
    {
      "public_id" => "0b6c9c2e-aaaa-bbbb-cccc-000000000001", "client_id" => "cid-1",
      "order_id" => "6123456789", "order_name" => "#1042", "order_total_cents" => 648_640,
      "currency" => "HUF", "country_code" => "HU", "ip" => "203.0.113.9", "user_agent" => "UA/1.0",
      "contact" => { "phone_e164" => "+36301234567", "email" => " Anna@Example.com ", "first_name" => "Anna", "last_name" => "Kiss" },
      "address" => { "country" => "HU", "province" => "BU", "city" => "Buda Pest", "zip" => "10 51" },
      "tracking" => {
        "fbp" => "fb.1.1.2", "fbc" => "", "ttp" => "ttp-1", "ttclid" => "", "ga_client_id" => "111.222",
        "page_url" => "https://brand.hu/products/widget", "consent" => { "analytics" => true, "marketing" => true }
      },
      "attribution" => { "utm_campaign" => "autumn", "fbclid" => "FBCLICK", "ttclid" => "TTCLICK", "gclid" => "G1",
                         "sccid" => "SC1", "epik" => "EPIK1" },
      "quote_snapshot" => {
        "currency" => "HUF", "total_cents" => 648_640, "shipping_cents" => 149_000,
        "tax" => { "amount_cents" => 0 }, "discount_code" => { "code" => "WELCOME10" },
        "lines" => [
          { "variant_id" => "44111", "product_id" => "8111", "title" => "Widget", "quantity" => 3,
            "unit_price_cents" => 199_900, "line_total_cents" => 449_700 }
        ]
      }
    }.merge(overrides)
  end

  def event(moment = "purchase", overrides = {})
    EB.build(session: session(overrides), moment: moment, now: NOW)
  end

  def pixel(platform, config = {}, extra = {})
    { "platform" => platform, "pixel_id" => "PIX1", "access_token" => "secret-token",
      "config" => { "server" => true, "purchase_event" => "purchase" }.merge(config) }.merge(extra)
  end

  def sha(text)
    Digest::SHA256.hexdigest(text)
  end

  # ---- event builder ----------------------------------------------------------------------

  def test_event_builder_purchase_uses_order_total_and_variant_ids
    e = event
    assert_equal 648_640, e["value_cents"]
    assert_equal "HUF", e["currency"]
    assert_equal [{ "id" => "44111", "product_id" => "8111", "title" => "Widget", "quantity" => 3, "price_cents" => 149_900 }],
                 e["contents"]
    assert_equal 3, e["num_items"]
    assert_equal "WELCOME10", e["coupon"]
  end

  def test_event_builder_builds_fbc_from_fbclid_when_cookie_missing
    assert_equal "fb.1.#{NOW * 1000}.FBCLICK", event["user"]["fbc"]
    with_cookie = event("purchase", "tracking" => { "fbc" => "fb.1.9.COOKIE" })
    assert_equal "fb.1.9.COOKIE", with_cookie["user"]["fbc"]
  end

  def test_event_builder_click_ids_fall_back_to_attribution
    user = event["user"]
    assert_equal "TTCLICK", user["ttclid"]
    assert_equal "SC1", user["sccid"]
    assert_equal "EPIK1", user["epik"]
    assert_equal "G1", user["gclid"]
  end

  def test_event_builder_consent_defaults_to_allowed
    assert_equal({ "analytics" => true, "marketing" => true, "sale_of_data" => true }, event["consent"])
    denied = event("purchase", "tracking" => { "consent" => { "marketing" => false, "analytics" => false } })
    refute denied["consent"]["marketing"]
    refute denied["consent"]["analytics"]
  end

  def test_event_builder_tolerates_empty_session
    e = EB.build(session: {}, moment: "initiate_checkout", now: NOW)
    assert_equal 0, e["value_cents"]
    assert_equal [], e["contents"]
  end

  # ---- Meta -------------------------------------------------------------------------------

  def test_meta_purchase_payload
    body = P.meta(pixel: pixel("meta", "test_event_code" => "TEST1"), event: event)
    data = body["data"].first
    assert_equal "Purchase", data["event_name"]
    assert_equal "order_6123456789_purchase", data["event_id"]
    assert_equal NOW, data["event_time"]
    assert_equal "website", data["action_source"]
    assert_equal "https://brand.hu/products/widget", data["event_source_url"]
    assert_equal "TEST1", body["test_event_code"]

    user = data["user_data"]
    assert_equal [sha("anna@example.com")], user["em"]
    assert_equal [sha("36301234567")], user["ph"]
    assert_equal [sha("anna")], user["fn"]
    assert_equal [sha("budapest")], user["ct"]
    assert_equal [sha("1051")], user["zp"]
    assert_equal [sha("hu")], user["country"]
    assert_equal "fb.1.1.2", user["fbp"]
    assert_equal "203.0.113.9", user["client_ip_address"]
    assert_equal "UA/1.0", user["client_user_agent"]

    custom = data["custom_data"]
    assert_in_delta 6486.40, custom["value"]
    assert_equal "HUF", custom["currency"]
    assert_equal ["44111"], custom["content_ids"]
    assert_equal [{ "id" => "44111", "quantity" => 3, "item_price" => 1499.0 }], custom["contents"]
    assert_equal 3, custom["num_items"]
    assert_equal "6123456789", custom["order_id"]
  end

  def test_meta_lead_and_initiate_checkout
    lead = P.meta(pixel: pixel("meta", "purchase_event" => "lead"), event: event)["data"].first
    assert_equal "Lead", lead["event_name"]
    assert_equal "order_6123456789_lead", lead["event_id"]

    ic = P.meta(pixel: pixel("meta"), event: event("initiate_checkout", "order_id" => nil, "order_total_cents" => nil))
    assert_equal "InitiateCheckout", ic["data"].first["event_name"]
    assert_equal "codkf_0b6c9c2e-aaaa-bbbb-cccc-000000000001_ic", ic["data"].first["event_id"]
    refute ic.key?("test_event_code")
  end

  def test_meta_payload_never_contains_raw_pii_or_token
    json = JSON.generate(P.meta(pixel: pixel("meta"), event: event))
    refute_includes json.downcase, "anna@example.com"
    refute_includes json, "36301234567"
    refute_includes json, "Kiss"
    refute_includes json, "secret-token"
  end

  def test_disabled_moment_gives_no_payload
    off = pixel("meta", "events" => { "purchase" => false })
    assert_nil P.meta(pixel: off, event: event)
    assert_nil P.tiktok(pixel: pixel("tiktok", "events" => { "form_open" => false }), event: event("initiate_checkout"))
  end

  def test_missing_email_and_phone_are_omitted_not_hashed_empty
    e = event("purchase", "contact" => {})
    user = P.meta(pixel: pixel("meta"), event: e)["data"].first["user_data"]
    refute user.key?("em")
    refute user.key?("ph")
  end

  # ---- TikTok -----------------------------------------------------------------------------

  def test_tiktok_purchase_payload
    body = P.tiktok(pixel: pixel("tiktok"), event: event)
    assert_equal "web", body["event_source"]
    assert_equal "PIX1", body["event_source_id"]
    data = body["data"].first
    assert_equal "CompletePayment", data["event"]
    assert_equal "order_6123456789_purchase", data["event_id"]
    assert_equal sha("anna@example.com"), data["user"]["email"]
    assert_equal sha("+36301234567"), data["user"]["phone"], "TikTok hashes the E.164 number with +"
    assert_equal "ttp-1", data["user"]["ttp"]
    assert_equal "TTCLICK", data["user"]["ttclid"]
    assert_equal "203.0.113.9", data["user"]["ip"]
    assert_in_delta 6486.40, data["properties"]["value"]
    assert_equal "product", data["properties"]["content_type"]
    assert_equal [{ "content_id" => "44111", "content_name" => "Widget", "quantity" => 3, "price" => 1499.0 }],
                 data["properties"]["contents"]
    assert_equal "https://brand.hu/products/widget", data["page"]["url"]
  end

  def test_tiktok_place_order_and_test_code
    body = P.tiktok(pixel: pixel("tiktok", "tiktok_event" => "place_order", "test_event_code" => "T9"), event: event)
    assert_equal "PlaceAnOrder", body["data"].first["event"]
    assert_equal "T9", body["test_event_code"]
  end

  # ---- GA4 --------------------------------------------------------------------------------

  def test_ga4_purchase_payload
    body = P.ga4(pixel: pixel("ga4"), event: event)
    assert_equal "111.222", body["client_id"]
    assert_equal NOW * 1_000_000, body["timestamp_micros"]
    assert_equal false, body["non_personalized_ads"]
    ev = body["events"].first
    assert_equal "purchase", ev["name"]
    params = ev["params"]
    assert_equal "6123456789", params["transaction_id"]
    assert_in_delta 6486.40, params["value"]
    assert_in_delta 1490.0, params["shipping"]
    assert_equal "WELCOME10", params["coupon"]
    assert_equal [{ "item_id" => "44111", "item_name" => "Widget", "price" => 1499.0, "quantity" => 3 }], params["items"]
    refute params.key?("tax")
  end

  def test_ga4_carries_no_pii
    json = JSON.generate(P.ga4(pixel: pixel("ga4"), event: event))
    refute_includes json.downcase, "anna"
    refute_includes json, "36301234567"
    refute_includes json, "203.0.113.9"
  end

  def test_ga4_begin_checkout_lead_and_client_id_fallback
    ic = P.ga4(pixel: pixel("ga4"), event: event("initiate_checkout"))
    assert_equal "begin_checkout", ic["events"].first["name"]
    refute ic["events"].first["params"].key?("transaction_id")

    lead = P.ga4(pixel: pixel("ga4", "purchase_event" => "lead"), event: event)
    assert_equal "generate_lead", lead["events"].first["name"]

    no_cookie = P.ga4(pixel: pixel("ga4"), event: event("purchase", "tracking" => {}))
    assert_equal "cid-1", no_cookie["client_id"]
  end

  def test_ga4_consent_denied_marks_non_personalized
    e = event("purchase", "tracking" => { "ga_client_id" => "1.2", "consent" => { "marketing" => false } })
    body = P.ga4(pixel: pixel("ga4"), event: e)
    assert_equal true, body["non_personalized_ads"]
    assert_equal "DENIED", body["consent"]["ad_user_data"]
  end

  # ---- Snapchat ---------------------------------------------------------------------------

  def test_snapchat_purchase_payload
    data = P.snapchat(pixel: pixel("snapchat"), event: event)["data"].first
    assert_equal "PURCHASE", data["event_name"]
    assert_equal "order_6123456789_purchase", data["event_id"], "top-level event_id pairs with client_dedup_id"
    assert_equal "WEB", data["action_source"]
    assert_equal [sha("anna@example.com")], data["user_data"]["em"]
    assert_equal [sha("36301234567")], data["user_data"]["ph"]
    assert_equal "SC1", data["user_data"]["sc_click_id"]
    assert_in_delta 6486.40, data["custom_data"]["value"]
    assert_equal "HUF", data["custom_data"]["currency"]
  end

  def test_snapchat_start_checkout_and_sign_up
    ic = P.snapchat(pixel: pixel("snapchat"), event: event("initiate_checkout"))["data"].first
    assert_equal "START_CHECKOUT", ic["event_name"]
    lead = P.snapchat(pixel: pixel("snapchat", "purchase_event" => "lead"), event: event)["data"].first
    assert_equal "SIGN_UP", lead["event_name"]
  end

  # ---- Pinterest --------------------------------------------------------------------------

  def test_pinterest_checkout_payload_uses_string_amounts
    data = P.pinterest(pixel: pixel("pinterest", "ad_account_id" => "549"), event: event)["data"].first
    assert_equal "checkout", data["event_name"]
    assert_equal "web", data["action_source"]
    assert_equal "order_6123456789_purchase", data["event_id"]
    assert_equal "6486.40", data["custom_data"]["value"]
    assert_equal [{ "id" => "44111", "item_price" => "1499.00", "quantity" => 3 }], data["custom_data"]["contents"]
    assert_equal "EPIK1", data["user_data"]["click_id"]
    assert_equal [sha("anna@example.com")], data["user_data"]["em"]
  end

  def test_pinterest_form_open_is_add_to_cart_and_lead
    ic = P.pinterest(pixel: pixel("pinterest"), event: event("initiate_checkout"))["data"].first
    assert_equal "add_to_cart", ic["event_name"]
    lead = P.pinterest(pixel: pixel("pinterest", "purchase_event" => "lead"), event: event)["data"].first
    assert_equal "lead", lead["event_name"]
  end

  # ---- shared -----------------------------------------------------------------------------

  def test_build_dispatches_by_platform_and_skips_google_ads
    assert_equal "Purchase", P.build(pixel: pixel("meta"), event: event)["data"].first["event_name"]
    assert_nil P.build(pixel: pixel("google_ads"), event: event)
  end

  def test_phone_normalisation
    assert_equal "36301234567", P.norm_phone_digits("+36 (30) 123-4567")
    assert_equal "+36301234567", P.norm_phone_e164("0036301234567")
    assert_nil P.norm_phone_digits("12345")
    assert_nil P.norm_phone_digits(nil)
  end

  def test_amounts_are_cents_over_100_for_every_currency
    assert_in_delta 12.34, P.amount(1234)
    assert_equal "0.00", P.amount_string(0)
    assert_nil P.amount(nil)
  end
end
