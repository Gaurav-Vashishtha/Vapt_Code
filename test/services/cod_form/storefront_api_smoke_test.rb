# Storefront API smoke test — the whole /api/form flow against in-memory stand-ins.
#
# Run it standalone (NOT through `rails test`: it defines its own ::Rails and fake models):
#
#   bundle exec ruby test/services/cod_form/storefront_api_smoke_test.rb
#
# Needs only activesupport, actionpack and rack-attack (all in the bundle). No database, Redis
# or Shopify. Covers: session -> quote -> contact -> OTP -> order (idempotency, replay, stale
# claim, async), token / origin / fallback handling, block lists, hand-off, upsell, events, geo,
# the webhook hook, the Rack::Attack throttles, and "no PII in the log".
if defined?(::Rails::Application)
  warn "[cod_form] storefront_api_smoke_test.rb is a standalone script; skipped inside the Rails test run"
else
  require_relative "support/storefront_smoke_harness"
  require "minitest/autorun"

  class SmokeTest < Minitest::Test
    PII = ["Anna", "Kiss", "anna@example.com", "301234567", "Fő utca"].freeze

    def setup; @shop = seed!; LOG.truncate(0); LOG.rewind; end

    def open_session(extra = {})
      api("POST", "session", { "v" => 37, "source" => "product", "locale" => "hu", "country" => "HU", "currency" => "HUF",
        "items" => [{ "variant_id" => "44111", "quantity" => 2, "properties" => {} }], "client_id" => "cid-1", "device" => "mobile",
        "attribution" => { "utm_source" => "fb" }, "tracking" => { "fbp" => "fb.1" }, "consent" => { "analytics" => true } }.merge(extra))
    end

    def order_body(token, sid, total, extra = {})
      { "token" => token, "idempotency_key" => "#{sid}:1", "items" => [{ "variant_id" => "44111", "quantity" => 2, "properties" => {} }],
        "contact" => { "first_name" => "Anna", "last_name" => "Kiss", "phone" => "301234567", "email" => "anna@example.com" },
        "address" => { "country" => "HU", "province" => "", "city" => "Budapest", "zip" => "1051", "address1" => "Fő utca 1", "address2" => "" },
        "custom_fields" => {}, "fields" => {}, "marketing_consent" => true, "shipping_rate_id" => 1, "bumps" => [], "payment_option_id" => "cod",
        "expected_total_cents" => total, "elapsed_ms" => 48_000, "codkf_company_url" => "", "tracking" => { "fbp" => "fb.1" }, "attribution" => {} }.merge(extra)
    end

    def aged!(sid); CodForm::Session.find_by(public_id: sid)["created_at"] = 1.minute.ago; end
    # token age comes from the token's iat: reissue an older token for the same session
    def old_token(sid)
      CodForm::Engine::SessionToken.issue(secret: Api::Form::BaseController.token_secret, shop_id: @shop.id, session_id: sid, issued_at: 60.seconds.ago.to_i)
    end

    def quote_total(token)
      s, b, = api("POST", "quote", { "token" => token, "seq" => 4, "items" => [{ "variant_id" => "44111", "quantity" => 2 }],
        "address" => { "country" => "HU", "city" => "Budapest", "zip" => "1051" }, "contact" => { "phone" => "301234567" }, "shipping_rate_id" => 1 })
      assert_equal 200, s, b.inspect
      b
    end

    def test_session_quote_order_flow
      s, b, = open_session
      assert_equal 200, s, b.inspect + LOG.string
      assert_nil b["fallback"]
      assert b["token"].start_with?("v1.")
      sid = b["session_id"]
      assert_equal "codkf_#{sid}_ic", b["event_ids"]["initiate_checkout"]
      assert_equal({ "min_submit_ms" => 3000, "honeypot" => "codkf_company_url" }, b["security"])
      assert_equal 399_800, b["quote"]["subtotal_cents"]
      refute b["quote"].keys.any? { |k| k.start_with?("_") }
      refute_includes b.to_json, "LEAK"
      refute_includes b.to_json, "test_event_code"
      assert_equal [{ "code" => "HU", "name" => "HU", "dial_code" => "36" }], b["countries"]
      assert_equal ["cf_form_open"], CodForm::FunnelLogger.events.map { |e| e[:type] }

      q = quote_total(b["token"])
      assert_equal 4, q["seq"]
      quote = q["quote"]
      assert_equal 149_000, quote["shipping_cents"]
      assert_equal 50_000, quote["cod_fee"]["amount_cents"]
      assert_equal 399_800 + 149_000 + 50_000, quote["total_cents"]
      assert_equal true, quote["eligibility"]["cod_allowed"]

      # contact
      s, c, = api("POST", "contact", { "token" => b["token"], "contact" => { "phone" => "06 30 123 4567", "email" => "Anna@Example.com" }, "country" => "HU" })
      assert_equal [200, { "ok" => true }], [s, c]
      row = CodForm::Session.find_by(public_id: sid)
      assert_equal "36301234567", row.phone_normalized
      assert_equal "anna@example.com", row.email_normalized

      # too fast -> bot
      s, e, = api("POST", "orders", order_body(b["token"], sid, quote["total_cents"], "elapsed_ms" => 500))
      assert_equal [422, "bot_suspected", "error_generic"], [s, e["error"]["code"], e["error"]["message_key"]]
      assert_equal "open", row.status

      token = old_token(sid)
      # honeypot
      s, e, = api("POST", "orders", order_body(token, sid, quote["total_cents"], "codkf_company_url" => "http://spam"))
      assert_equal [422, "bot_suspected"], [s, e["error"]["code"]]
      # wrong expected total -> 409 with quote, nothing created
      s, e, = api("POST", "orders", order_body(token, sid, 1))
      assert_equal [409, "total_changed"], [s, e["error"]["code"]]
      assert_equal quote["total_cents"], e["quote"]["total_cents"]
      assert_empty ShopifyServices::CodOrderCreateService.calls
      assert_equal "open", row.status
      # validation
      s, e, = api("POST", "orders", order_body(token, sid, quote["total_cents"], "contact" => { "first_name" => "", "phone" => "12" }))
      assert_equal [422, "validation_failed"], [s, e["error"]["code"]]
      assert e["error"]["fields"].key?("phone"), e.inspect
      assert e["error"]["fields"].key?("first_name"), e.inspect
      # foreign idempotency key
      s, e, = api("POST", "orders", order_body(token, sid, quote["total_cents"], "idempotency_key" => "other-session:1"))
      assert_equal [400, "invalid_request"], [s, e["error"]["code"]]

      # success
      s, o, = api("POST", "orders", order_body(token, sid, quote["total_cents"]))
      assert_equal 201, s, o.inspect + LOG.string
      assert_equal({ "id" => "6123456789", "name" => "#1042", "number" => 1042, "total_cents" => quote["total_cents"], "currency" => "HUF",
                     "status_url" => "https://brand.hu/orders/abc" }, o["order"])
      assert_equal "order_6123456789_purchase", o["events"]["purchase_event_id"]
      assert_equal "5988.00", o["web_pixel"]["totalPrice"]
      assert_equal "order_status", o["thank_you"]["type"]
      assert_equal 1, ShopifyServices::CodOrderCreateService.calls.size
      args, kw = ShopifyServices::CodOrderCreateService.calls.first
      assert_equal [{}, {}, {}, nil, nil, false], args[1..]
      input = kw[:form_context][:draft_input]
      assert_equal quote["total_cents"], kw[:form_context][:expected_total_cents]
      assert_equal "gid://shopify/ProductVariant/44111", input["lineItems"][0]["variantId"]
      assert_equal "Utánvét díj", input["lineItems"].last["title"]
      assert_equal "+36301234567", input["phone"]
      assert_equal "anna@example.com", input["email"]
      assert_equal({ "customerId" => "gid://shopify/Customer/77" }, input["purchasingEntity"])
      assert_includes input["tags"], "codking_form"
      refute_includes input["tags"], "✅ COD-Verified"
      assert_equal sid, input["customAttributes"].find { |a| a["key"] == "_codkFormSessionId" }["value"]
      refute input["customAttributes"].any? { |a| a["key"] == "_otpVerifiedPhoneNumber" }
      assert_equal "HUF", input["presentmentCurrencyCode"]
      assert_equal "ordered", row.status
      assert_equal "6123456789", row.order_id
      assert_equal true, row.custom_fields["marketing_consent"]
      assert_equal 1, CodForm::OrderUsage.rows.first.orders_count
      assert_equal [[row.id]], CodForm::PostOrderJob.jobs.last(1)
      assert_includes CodForm::FunnelLogger.events.map { |e| e[:type] }, "cf_order_created"

      # replay: same body, HTTP 200, no second order
      s, r, = api("POST", "orders", order_body(token, sid, quote["total_cents"]))
      assert_equal 200, s
      assert_equal o, r
      s, r2, = api("POST", "orders", order_body(token, sid, quote["total_cents"], "idempotency_key" => "#{sid}:2"))
      assert_equal [200, o], [s, r2]
      assert_equal 1, ShopifyServices::CodOrderCreateService.calls.size
      s, st, = api("POST", "orders/status", { "token" => token })
      assert_equal [200, o], [s, st]

      PII.each { |needle| refute_includes LOG.string, needle, "PII in log: #{needle}" }
      refute_includes LOG.string, token
    end

    def test_concurrent_submit_is_rejected_and_stale_claim
      _, b, = open_session
      sid = b["session_id"]; token = old_token(sid)
      total = quote_total(token)["quote"]["total_cents"]
      row = CodForm::Session.find_by(public_id: sid)
      row.update_columns(status: "ordering", updated_at: Time.current)
      s, e, = api("POST", "orders", order_body(token, sid, total))
      assert_equal [409, "already_processing", 1500], [s, e["error"]["code"], e["poll_after_ms"]]
      assert_empty ShopifyServices::CodOrderCreateService.calls
      s, st, = api("POST", "orders/status", { "token" => token })
      assert_equal [202, "processing"], [s, st["status"]]
    end

    def test_order_failure_resets_session_and_total_changed_from_shopify
      _, b, = open_session
      sid = b["session_id"]; token = old_token(sid)
      total = quote_total(token)["quote"]["total_cents"]
      row = CodForm::Session.find_by(public_id: sid)

      ShopifyServices::CodOrderCreateService.result = { error: "boom", code: "complete_failed" }
      s, e, = api("POST", "orders", order_body(token, sid, total))
      assert_equal [502, "order_failed"], [s, e["error"]["code"]]
      assert_equal ["open", "order_failed"], [row.status, row.order_error]
      s, st, = api("POST", "orders/status", { "token" => token })
      assert_equal [502, "order_failed"], [s, st["order_error"]]

      ShopifyServices::CodOrderCreateService.result = { error: "x", code: "total_changed", draft_total_cents: total + 700 }
      s, e, = api("POST", "orders", order_body(token, sid, total, "idempotency_key" => "#{sid}:2"))
      assert_equal [409, "total_changed", total + 700], [s, e["error"]["code"], e["quote"]["total_cents"]]
      # the quote endpoint now agrees with Shopify, and the confirmed total is accepted
      assert_equal total + 700, quote_total(token)["quote"]["total_cents"]
      ShopifyServices::CodOrderCreateService.result = ->(kw) { { success: true, order_id: 1, order_number: 1, order_name: "#1", order_status_url: nil, draft_total_cents: kw[:form_context][:expected_total_cents] } }
      s, o, = api("POST", "orders", order_body(token, sid, total + 700, "idempotency_key" => "#{sid}:3"))
      assert_equal 201, s, o.inspect
      assert_equal total + 700, ShopifyServices::CodOrderCreateService.calls.last[1][:form_context][:expected_total_cents]
      assert_equal "message", o["thank_you"]["type"]
    end

    def test_token_and_origin_and_fallbacks
      s, e, = open_session.then { |st, body, _| api("POST", "quote", { "token" => body["token"] + "x" }) }
      assert_equal [401, "invalid_token"], [s, e["error"]["code"]]
      s, e, = api("POST", "quote", {})
      assert_equal [401, "invalid_token"], [s, e["error"]["code"]]
      s, e, = api("POST", "session", {}, origin: "https://evil.com")
      assert_equal [403, "origin_not_allowed", "checkout"], [s, e["error"]["code"], e["error"]["fallback"]]
      s, e, = api("POST", "session", {}, origin: nil)
      assert_equal 403, s
      s, e, = api("POST", "session", {}, shop: "nope.myshopify.com")
      assert_equal [404, "shop_not_found"], [s, e["error"]["code"]]
      s, e, = api("POST", "session", nil, raw: "{not json")
      assert_equal [400, "invalid_request"], [s, e["error"]["code"]]
      s, e, = api("POST", "session", nil, raw: "[1]")
      assert_equal 400, s
      s, e, = api("POST", "session", nil, raw: "{\"a\":\"#{'x' * 70_000}\"}")
      assert_equal 400, s

      # token of another shop
      other = Shop.create!(shopify_domain: "other.myshopify.com", primary_domain: "https://brand.hu")
      CodForm::ShopConfig.create!(shop_id: other.id)
      _, b, = open_session
      s, e, = api("POST", "quote", { "token" => b["token"] }, shop: "other.myshopify.com")
      assert_equal [401, "invalid_token"], [s, e["error"]["code"]]

      # expired session row
      CodForm::Session.find_by(public_id: b["session_id"]).update_columns(expires_at: 1.minute.ago)
      s, e, = api("POST", "quote", { "token" => b["token"] })
      assert_equal [401, "token_expired"], [s, e["error"]["code"]]

      # fallbacks are 200 without a token
      s, f, = open_session("country" => "DE")
      assert_equal [200, true, "not_eligible_country", nil], [s, f["ok"], f["fallback"], f["token"]]
      s, f, = open_session("items" => [{ "variant_id" => "999", "quantity" => 1 }])
      assert_equal "config_error", f["fallback"]
      s, f, = open_session("items" => [{ "variant_id" => "44111", "quantity" => 2, "properties" => { "_bundle" => "1" }, "cart_line_price_cents" => 100 }])
      assert_equal "bundle_cart", f["fallback"]
      CodForm::OrderUsage.create!(shop_id: @shop.id, period: Time.current.in_time_zone("Europe/Budapest").strftime("%Y-%m"), orders_count: 70)
      Rails.cache.clear
      s, f, = open_session
      assert_equal ["cap_reached", { "state" => "fallback" }], [f["fallback"], f["cap"]]
      # a staff preview session ignores the cap and is flagged as test
      s, t, = open_session("preview_token" => "a" * 32)
      assert_equal [nil, true], [t["fallback"], t["test"]]
      CodForm::OrderUsage.reset!; Rails.cache.clear
      CodForm::ShopConfig.rows.first.update_columns(storefront_mode: "legacy")
      s, f, = open_session
      assert_equal "module_disabled", f["fallback"]
      s, t2, = open_session("preview_token" => "a" * 32)
      assert_nil t2["fallback"]
      s, q, = api("POST", "quote", { "token" => t2["token"], "seq" => 1 })
      assert_equal 200, s
      s, e, = api("POST", "quote", { "token" => b["token"] })
      assert_includes [401, 403], s
      CodForm::GlobalSetting.current.update_columns(kill_switch: true)
      s, f, = open_session("preview_token" => "a" * 32)
      assert_equal "kill_switch", f["fallback"]
      s, e, = api("POST", "quote", { "token" => t2["token"] })
      assert_equal [503, "kill_switch", "checkout"], [s, e["error"]["code"], e["error"]["fallback"]]
    end

    def test_block_list_and_limits
      _, b, = open_session
      sid = b["session_id"]; token = old_token(sid)
      total = quote_total(token)["quote"]["total_cents"]
      CodForm::BlockEntry.create!(shop_id: @shop.id, kind: "phone", value_normalized: "301234567")
      CodForm::ShopConfig.rows.first.update_columns(fraud: { "blocked_message" => "No COD" })
      q = quote_total(token)["quote"]
      assert_equal [false, ["phone_blocked"], "No COD", true], q["eligibility"].values_at("cod_allowed", "reasons", "message", "pay_online")
      s, e, = api("POST", "orders", order_body(token, sid, total))
      assert_equal [422, "blocked", "No COD"], [s, e["error"]["code"], e["error"]["message"]]
      row = CodForm::Session.find_by(public_id: sid)
      assert_equal "blocked", row.status
      rej = CodForm::Rejection.rows.last
      assert_equal ["phone_blocked", "order", "phone"], [rej.reason_code, rej.stage, rej.subject_kind]
      refute_includes rej.subject_masked, "30123"
      assert_empty ShopifyServices::CodOrderCreateService.calls
      # Pay online hand-off still works for a blocked buyer
      s, h, = api("POST", "handoff", { "token" => token, "kind" => "prepaid", "reason" => "blocked",
        "contact" => { "first_name" => "Anna", "phone" => "301234567", "email" => "" },
        "address" => { "country" => "HU", "city" => "Budapest", "zip" => "1051", "address1" => "Fő utca 1" },
        "items" => [{ "variant_id" => "44111", "quantity" => 2 }] })
      assert_equal 200, s, h.inspect + LOG.string
      assert_equal [sid, "1"], h["cart_attributes"].values_at("_codkFormSessionId", "_codkFormId")
      refute h["cart_attributes"].key?("_otpVerifiedPhoneNumber")
      refute h["buyer_identity"].key?("email")
      assert_equal "+36301234567", h["buyer_identity"]["phone"]
      assert_equal "handoff_prepaid", row.status
      assert_equal "cf_prepaid_redirect", CodForm::FunnelLogger.events.last[:type]
      s, e, = api("POST", "handoff", { "token" => token, "kind" => "partial", "payment_option_id" => "rule_99" })
      assert_equal 400, s
    end

    def test_otp_flow
      CodForm::ShopConfig.rows.first.update_columns(general: { "countries" => ["HU"], "otp" => { "enabled" => true } })
      _, b, = open_session
      sid = b["session_id"]; token = old_token(sid)
      assert_equal({ "enabled" => true, "mode" => "before_order", "channels" => ["sms"], "max_attempts" => 3, "resend_wait_seconds" => 30, "code_length" => 4 }, b["otp"])
      total = quote_total(token)["quote"]["total_cents"]
      assert_equal true, quote_total(token)["quote"]["otp_required"]
      s, e, = api("POST", "orders", order_body(token, sid, total))
      assert_equal [428, "otp_required"], [s, e["error"]["code"]]

      NetworkServices::SendPreOrderOtpService.result = { status: "Success", Notes: "sent" }
      s, r, = api("POST", "otp/send", { "token" => token, "phone" => "301234567", "country" => "HU", "channel" => "sms" })
      assert_equal 200, s, r.inspect + LOG.string
      assert_equal [true, "sms", 30, 2], r.values_at("sent", "channel", "resend_wait_seconds", "attempts_left")
      refute_includes r["masked_phone"], "30123"
      sent = NetworkServices::SendPreOrderOtpService.calls.last
      assert_equal({ "country_code" => "HU", "phone" => "301234567", "mode" => "SMS", "ip_address" => "203.0.113.9", "device_id" => sid }, sent.slice("country_code", "phone", "mode", "ip_address", "device_id"))
      refute sent.key?("cart_details")
      row = CodForm::Session.find_by(public_id: sid)
      assert_equal "otp_pending", row.status
      # resend too early
      s, e, = api("POST", "otp/send", { "token" => token, "phone" => "301234567", "country" => "HU" })
      assert_equal [429, "otp_throttled"], [s, e["error"]["code"]]
      assert e["error"]["retry_after"].positive?

      NetworkServices::VerifyPreOrderOtpService.code = "4821"
      s, e, = api("POST", "otp/verify", { "token" => token, "phone" => "301234567", "country" => "HU", "code" => "0000" })
      assert_equal [422, "otp_invalid", 4], [s, e["error"]["code"], e["attempts_left"]]
      s, v, = api("POST", "otp/verify", { "token" => token, "phone" => "301234567", "country" => "HU", "code" => "4821" })
      assert_equal [200, { "ok" => true, "verified" => true }], [s, v]
      refute_includes v.to_json, "SECRET-SSO"
      assert row.otp_verified_at

      # a different phone than the verified one needs OTP again
      s, e, = api("POST", "orders", order_body(token, sid, total, "contact" => { "first_name" => "Anna", "phone" => "301234568" }))
      assert_equal [428, "otp_required"], [s, e["error"]["code"]]
      s, o, = api("POST", "orders", order_body(token, sid, total))
      assert_equal 201, s, o.inspect + LOG.string
      args, kw = ShopifyServices::CodOrderCreateService.calls.last
      assert_equal true, args[6]
      input = kw[:form_context][:draft_input]
      assert_includes input["tags"], "✅ COD-Verified"
      assert_equal "+36301234567", input["customAttributes"].find { |a| a["key"] == "_otpVerifiedPhoneNumber" }["value"]
      assert_equal sid, input["customAttributes"].find { |a| a["key"] == "_codkSessionId" }["value"]
      refute_includes LOG.string, "4821"
    end

    def test_otp_bypass_when_send_fails_on_our_side
      CodForm::ShopConfig.rows.first.update_columns(general: { "countries" => ["HU"], "otp" => { "enabled" => true } })
      _, b, = open_session
      sid = b["session_id"]; token = old_token(sid)
      total = quote_total(token)["quote"]["total_cents"]
      NetworkServices::SendPreOrderOtpService.result = { status: "Error", Notes: "OTP balance is exhausted" }
      s, r, = api("POST", "otp/send", { "token" => token, "phone" => "301234567", "country" => "HU" })
      assert_equal [200, { "ok" => true, "sent" => false, "bypass" => true }], [s, r]
      assert_equal "cf_otp_bypassed", CodForm::FunnelLogger.events.last[:type]
      assert_equal [[@shop.id]], CodForm::OtpUnavailableNotifyJob.jobs.last(1)
      s, o, = api("POST", "orders", order_body(token, sid, total))
      assert_equal 201, s, o.inspect
      input = ShopifyServices::CodOrderCreateService.calls.last[1][:form_context][:draft_input]
      refute_includes input["tags"], "✅ COD-Verified"
      refute input["customAttributes"].any? { |a| a["key"] == "_otpVerifiedPhoneNumber" }

      # throttled / blocked never bypass
      _, b2, = open_session
      NetworkServices::SendPreOrderOtpService.result = { "status" => "Error", "code" => "pre_order_otp_throttled" }
      s, e, = api("POST", "otp/send", { "token" => b2["token"], "phone" => "301234569", "country" => "HU" })
      assert_equal [429, "otp_throttled"], [s, e["error"]["code"]]
      NetworkServices::SendPreOrderOtpService.result = { "status" => "Error", "code" => "pre_order_otp_phone_blocked" }
      s, e, = api("POST", "otp/send", { "token" => b2["token"], "phone" => "301234570", "country" => "HU" })
      assert_equal [422, "blocked"], [s, e["error"]["code"]]
      s, e, = api("POST", "otp/send", { "token" => b2["token"], "phone" => "12", "country" => "HU" })
      assert_equal [422, "validation_failed", "error_phone"], [s, e["error"]["code"], e["error"]["fields"]["phone"]]
    end

    def test_upsell
      CodForm::Offer.create!(shop_id: @shop.id, offer_type: "upsell", name: "U", config: { "variant_id" => "44123", "quantity" => 1, "discount_type" => "percentage", "value" => 20 })
      _, b, = open_session
      assert_equal true, b["offers"]["upsell_enabled"]
      sid = b["session_id"]; token = old_token(sid)
      total = quote_total(token)["quote"]["total_cents"]
      s, o, = api("POST", "orders", order_body(token, sid, total))
      assert_equal 201, s, o.inspect + LOG.string
      assert_equal [1, 99_900, 79_920], [o["upsell"]["offer_id"], o["upsell"]["variant"]["price_cents"], o["upsell"]["variant"]["discounted_price_cents"]]
      s, e, = api("POST", "upsell_accept", { "token" => token, "offer_id" => 999, "accept" => true })
      assert_equal [410, "upsell_expired"], [s, e["error"]["code"]]
      s, a, = api("POST", "upsell_accept", { "token" => token, "offer_id" => 1, "accept" => true })
      assert_equal 200, s, a.inspect + LOG.string
      assert_equal({ "variant_id" => "44123", "quantity" => 1, "price_cents" => 79_920 }, a["added"])
      assert_equal total + 79_920, a["order"]["total_cents"]
      edit = ShopifyServices::OrderEditAddLineService.calls.last
      assert_equal({ "type" => "percentage", "value" => 20.0 }, edit[:discount])
      assert_equal ["codking_upsell"], ShopifyServices::OrderTagPostService.calls.last[2..]
      s, e, = api("POST", "upsell_accept", { "token" => token, "offer_id" => 1, "accept" => true })
      assert_equal 410, s
    end

    def test_events_and_geo
      s, body, = api("POST", "events", { "token" => nil, "client_id" => "cid", "events" => [{ "type" => "cf_button_view", "at" => Time.now.iso8601, "meta" => {} }] })
      assert_equal [204, nil], [s, body]
      assert_equal 1, CodForm::EventIngestService.calls.last[:events].size
      s, = api("POST", "events", nil, raw: "garbage")
      assert_equal 204, s
      s, = api("POST", "events", { "events" => [] }, origin: "https://evil.com")
      assert_equal 204, s

      s, g, h = api("GET", "geo/pk")
      assert_equal 200, s, g.inspect + LOG.string
      assert_equal ["PK", 7, "by_province"], [g["country"], g["provinces"].size, g["cities"]["mode"]]
      assert_equal "92", g["schema"]["dial_code"]
      assert_equal %w[max-age=86400 public], h["cache-control"].split(", ").sort
      s, g, = api("GET", "geo/de")
      assert_equal [200, [], "free"], [s, g["provinces"], g["cities"]["mode"]]
      s, g, = api("GET", "geo/in/postal/411001")
      assert_equal [200, { "found" => false }], [s, g]
      s, = api("GET", "geo/pk", nil, origin: "https://evil.com")
      assert_equal 403, s
    end

    def test_webhook_hook
      _, b, = open_session
      row = CodForm::Session.find_by(public_id: b["session_id"])
      order = { "id" => 555, "source_name" => "shopify_draft_order", "note_attributes" => [{ "name" => "_codkFormSessionId", "value" => row.public_id }] }
      assert_same order, CodForm::OrderWebhookHook.normalize(order, @shop)           # session has no order
      row.update_columns(status: "ordering")
      out = CodForm::OrderWebhookHook.normalize(order, @shop)                          # in flight: ours
      assert_equal ["codking_form", true], out.values_at("source_name", "_codk_form")
      assert_equal "shopify_draft_order", order["source_name"]
      row.update_columns(status: "ordered", order_id: "555")
      assert_equal "codking_form", CodForm::OrderWebhookHook.normalize(order, @shop)["source_name"]
      row.update_columns(order_id: "556")
      assert_same order, CodForm::OrderWebhookHook.normalize(order, @shop)
      other = { "id" => 1, "source_name" => "shopify_draft_order", "note_attributes" => [] }
      assert_same other, CodForm::OrderWebhookHook.normalize(other, @shop)
      assert_nil CodForm::OrderWebhookHook.normalize(nil, @shop)
      bad = { "id" => 2, "note_attributes" => [{ "name" => "_codkFormSessionId", "value" => "'; drop" }] }
      assert_same bad, CodForm::OrderWebhookHook.normalize(bad, @shop)
    end
  end


  class Rule < OpenStruct; def as_json(*); to_h.transform_keys(&:to_s); end; end
  class Shop; attr_accessor :rules; def partial_rule_sets; FakeRelation.new(nil, (rules || []).map { |r| FakeRecord === r ? r : RuleRow.new(r) }); end; end
  class RuleRow
    def initialize(h); @h = h.stringify_keys; end
    def [](k); @h[k.to_s]; end
    def as_json(*); @h; end
  end

  class Smoke2 < Minitest::Test
    def setup; @shop = seed!; LOG.truncate(0); LOG.rewind; CodForm::PostOrderJob.jobs.clear; end

    def open_session(extra = {})
      api("POST", "session", { "source" => "product", "locale" => "hu", "country" => "HU", "items" => [{ "variant_id" => "44111", "quantity" => 2 }],
                               "client_id" => "cid-1", "device" => "mobile" }.merge(extra))
    end
    def old_token(sid); CodForm::Engine::SessionToken.issue(secret: Api::Form::BaseController.token_secret, shop_id: @shop.id, session_id: sid, issued_at: 60.seconds.ago.to_i, test: CodForm::Session.find_by(public_id: sid).is_test); end
    def base(token, extra = {})
      { "token" => token, "items" => [{ "variant_id" => "44111", "quantity" => 2 }], "shipping_rate_id" => 1,
        "contact" => { "first_name" => "Anna", "phone" => "301234567", "email" => "" },
        "address" => { "country" => "HU", "city" => "Budapest", "zip" => "1051", "address1" => "Fő utca 1" } }.merge(extra)
    end
    def quote(token, extra = {}); s, b, = api("POST", "quote", base(token, extra)); assert_equal 200, s, b.inspect + LOG.string; b["quote"]; end
    def order(token, sid, total, extra = {})
      api("POST", "orders", base(token, { "idempotency_key" => "#{sid}:1", "payment_option_id" => "cod", "expected_total_cents" => total, "elapsed_ms" => 9000 }.merge(extra)))
    end

    def test_partial_handoff_and_payment_options
      @shop.setting["partial_payment_enabled"] = true
      @shop.rules = [{ "id" => 17, "is_enabled" => true, "amount_type" => "fixed", "amount" => "1000.0", "position" => 0, "product_scope" => "all" }]
      _, b, = open_session
      assert_equal "sf-token", b["handoff"]["storefront_token"]
      sid = b["session_id"]; token = old_token(sid)
      q = quote(token)
      ids = q["payment_options"]["options"].map { |o| o["id"] }
      assert_equal ["cod", "rule_17"], ids
      assert_equal "cod", q["payment_options"]["default_id"]
      # a partial option cannot be submitted as an order
      s, e, = order(token, sid, q["total_cents"], "payment_option_id" => "rule_17")
      assert_equal [400, "invalid_request"], [s, e["error"]["code"]]
      s, h, = api("POST", "handoff", base(token, "kind" => "partial", "payment_option_id" => "rule_17", "reason" => "buyer_choice"))
      assert_equal 200, s, h.inspect + LOG.string
      a = h["cart_attributes"]
      assert_equal ["fixed", "1000.0", "45999", "[44111]", true], a.values_at("_codkAmountType", "_codkAmountValue", "_partial_product_variant", "partial_payment_variants", "_partialPaymentProduct")
      assert_equal "/checkout", h["checkout_path"]
      assert_equal "HU", h["buyer_identity"]["countryCode"]
      assert_equal "Fő utca 1", h["buyer_identity"]["deliveryAddressPreferences"][0]["deliveryAddress"]["address1"]
      row = CodForm::Session.find_by(public_id: sid)
      assert_equal ["handoff_partial", 17], [row.status, row.partial_rule_set_id]
      assert_equal "45999", @shop.setting.partial_dummy_variant_id
      # COD submit after a hand-off is refused (not orderable)
      s, e, = order(token, sid, q["total_cents"])
      assert_equal 409, s

      # webhook: the checkout order of this hand-off is tagged, counted and closes the session
      params = { "id" => 9001, "name" => "#2001", "total_price" => "5988.00", "currency" => "HUF", "source_name" => "web",
                 "note_attributes" => [{ "name" => "_codkFormSessionId", "value" => sid }] }
      assert_same params, CodForm::OrderWebhookHook.normalize(params, @shop)
      CodForm::OrderWebhookHook.after(@shop, params)
      assert_equal ["ordered", "9001", 598_800], [row.status, row.order_id, row.order_total_cents]
      assert_equal %w[codking_form codking_form_partial], ShopifyServices::OrderTagPostService.calls.last(2).map { |c| c[2] }
      usage = CodForm::OrderUsage.rows.first
      assert_equal [1, 1], [usage.orders_count, usage.partial_orders_count]
      assert_equal ["cf_order_created", true], [CodForm::FunnelLogger.events.last[:type], CodForm::FunnelLogger.events.last[:meta]["partial"]]
      CodForm::OrderWebhookHook.after(@shop, params) # idempotent
      assert_equal 1, usage.orders_count
    end

    def test_offers_bump_discount_downsell
      CodForm::Offer.create!(shop_id: @shop.id, offer_type: "quantity", name: "Q", config: { "tiers" => [
        { "quantity" => 1, "discount_type" => "none", "value" => 0 }, { "quantity" => 2, "discount_type" => "percentage", "value" => 10, "label" => { "default" => "2 packs" } }], "apply_to_higher_quantities" => true })
      CodForm::Offer.create!(shop_id: @shop.id, offer_type: "bump", name: "B", config: { "kind" => "custom", "title" => { "default" => "Express" }, "price_cents" => 49_900 })
      CodForm::Offer.create!(shop_id: @shop.id, offer_type: "downsell", name: "D", config: { "discount_type" => "percentage", "value" => 10, "title" => { "default" => "Wait" } })
      CodForm::Offer.create!(shop_id: @shop.id, offer_type: "threshold", name: "T", config: { "kind" => "free_shipping", "threshold_cents" => 100 }) # pro gate: must be absent
      _, b, = open_session
      assert_equal 1, b["offers"]["quantity"]["id"]
      assert_equal [{ "id" => 2, "unit_price_cents" => 49_900 }], b["offers"]["bumps"].map { |x| x.slice("id", "unit_price_cents") }
      assert_equal 3, b["offers"]["downsell"]["id"]
      assert_equal [], b["offers"]["thresholds"]
      sid = b["session_id"]; token = old_token(sid)
      q = quote(token, "bumps" => [{ "offer_id" => 2, "quantity" => 1 }], "downsell_offer_id" => 3)
      assert_equal 399_800, q["subtotal_cents"]
      kinds = q["discounts"].map { |d| d["kind"] }
      assert_equal %w[quantity_offer downsell], kinds
      assert_equal 149_000, q["shipping_cents"]
      assert_equal q["merchandise_total_cents"] + q["shipping_cents"] + q["cod_fee"]["amount_cents"], q["total_cents"]
      # client cannot lower the price: a fake line price is ignored
      q2 = quote(token, "items" => [{ "variant_id" => "44111", "quantity" => 2, "price" => 1, "unit_price_cents" => 1 }], "bumps" => [{ "offer_id" => 2, "quantity" => 1 }], "downsell_offer_id" => 3)
      assert_equal q["total_cents"], q2["total_cents"]
      s, o, = order(token, sid, q["total_cents"], "bumps" => [{ "offer_id" => 2, "quantity" => 1 }], "downsell_offer_id" => 3)
      assert_equal 201, s, o.inspect + LOG.string
      input = ShopifyServices::CodOrderCreateService.calls.last[1][:form_context][:draft_input]
      assert_equal 3, input["lineItems"].size
      assert input["lineItems"][0]["appliedDiscount"]
      assert_equal "Express", input["lineItems"][1]["title"]

      # discount code: the field is off by default -> invalid, order refused
      _, b2, = open_session
      t2 = old_token(b2["session_id"])
      q3 = quote(t2, "discount_code" => "WELCOME10")
      assert_equal "invalid", q3["discount_code"]["status"]
      s, e, = order(t2, b2["session_id"], q3["total_cents"], "discount_code" => "WELCOME10")
      assert_equal [422, "discount_invalid"], [s, e["error"]["code"]]
    end

    def test_preview_session_order_is_a_test_order
      CodForm::BlockEntry.create!(shop_id: @shop.id, kind: "phone", value_normalized: "301234567")
      _, b, = open_session("preview_token" => "a" * 32)
      assert_equal true, b["test"]
      sid = b["session_id"]; token = old_token(sid)
      q = quote(token)
      assert_equal true, q["eligibility"]["cod_allowed"]
      s, o, = order(token, sid, q["total_cents"])
      assert_equal [201, true], [s, o["test"]], o.inspect + LOG.string
      input = ShopifyServices::CodOrderCreateService.calls.last[1][:form_context][:draft_input]
      assert_includes input["tags"], "codking_form_test"
      usage = CodForm::OrderUsage.rows.first
      assert_equal [0, 1], [usage.orders_count, usage.test_orders_count]
      assert CodForm::ShopConfig.rows.first.setup_state["test_order_at"]
      # a forged "test" token for a live session is rejected
      _, live, = open_session
      forged = CodForm::Engine::SessionToken.issue(secret: Api::Form::BaseController.token_secret, shop_id: @shop.id, session_id: live["session_id"], issued_at: Time.now.to_i, test: true)
      s, e, = api("POST", "quote", { "token" => forged })
      assert_equal [401, "invalid_token"], [s, e["error"]["code"]]
    end

    def test_async_orders
      CodForm::GlobalSetting.current.update_columns(async_orders: true)
      _, b, = open_session
      sid = b["session_id"]; token = old_token(sid)
      q = quote(token)
      s, o, = order(token, sid, q["total_cents"]) # ApplicationJob fake runs the job inline
      assert_equal 201, s, o.inspect + LOG.string
      assert_equal "6123456789", o["order"]["id"]
      assert_equal 1, ShopifyServices::CodOrderCreateService.calls.size
      row = CodForm::Session.find_by(public_id: sid)
      assert_equal "ordered", row.status
    end

    def test_stale_ordering_adopts_webhook_order
      _, b, = open_session
      sid = b["session_id"]; token = old_token(sid)
      q = quote(token)
      row = CodForm::Session.find_by(public_id: sid)
      row.update_columns(status: "ordering", updated_at: 10.minutes.ago, tracking: { "webhook_order_id" => "777" })
      Object.const_set(:ShopifyAPI, Module.new) unless defined?(ShopifyAPI)
      ShopifyAPI.const_set(:Order, Class.new { def self.find(id); OpenStruct.new(id: id, name: "#77", order_number: 77, total_price: "5988.00", currency: "HUF", order_status_url: "https://x/s"); end }) unless defined?(ShopifyAPI::Order)
      s, o, = order(token, sid, q["total_cents"])
      assert_equal [200, "777", "#77"], [s, o["order"]["id"], o["order"]["name"]], o.inspect + LOG.string
      assert_empty ShopifyServices::CodOrderCreateService.calls
      assert_equal ["ordered", "777"], [row.status, row.order_id]
      # without a webhook order id the stale session is simply taken over
      _, b2, = open_session
      sid2 = b2["session_id"]; t2 = old_token(sid2)
      q2 = quote(t2)
      CodForm::Session.find_by(public_id: sid2).update_columns(status: "ordering", updated_at: 10.minutes.ago)
      s, o2, = order(t2, sid2, q2["total_cents"])
      assert_equal 201, s, o2.inspect + LOG.string
    end

    def test_tax_exclusive_shop_and_order_first_and_cod_rules
      CodForm::CatalogService.singleton_class.class_eval do
        alias_method :orig_admin_query, :admin_query
        define_method(:admin_query) do |shop, query, variables = {}|
          if query.include?("currencyFormats")
            [{ "shop" => { "currencyCode" => "HUF", "taxesIncluded" => false, "currencyFormats" => { "moneyFormat" => "{{amount}} Ft" } } }, []]
          elsif query.include?("taxLines")
            $tax_inputs << variables["input"]
            [{ "draftOrderCalculate" => { "calculatedDraftOrder" => { "totalTaxSet" => { "presentmentMoney" => { "amount" => "270.00" } },
               "totalPriceSet" => { "presentmentMoney" => { "amount" => "6258.00" } }, "taxLines" => [{ "title" => "ÁFA", "rate" => 0.27, "priceSet" => { "presentmentMoney" => { "amount" => "270.00" } } }] }, "userErrors" => [] } }, []]
          else
            orig_admin_query(shop, query, variables)
          end
        end
      end
      $tax_inputs = []
      @shop.setting["selected_zips"] = "1051, 20*"
      CodForm::ShopConfig.rows.first.update_columns(general: { "countries" => ["HU"], "otp" => { "enabled" => true, "mode" => "order_first" } })
      _, b, = open_session
      assert_equal "order_first", b["otp"]["mode"]
      assert_equal ["none", true], b["quote"]["tax"].values_at("status", "required")
      sid = b["session_id"]; token = old_token(sid)
      # With a complete address the tax is always confirmed with Shopify, whether or not the
      # client asked (want_tax): the shop-level flag does not predict the draft order's total.
      q = quote(token)
      assert_equal 1, $tax_inputs.size, "tax is calculated as soon as the address is complete"
      assert_equal ["calculated", 27_000], q["tax"].values_at("status", "amount_cents")
      q = quote(token, "want_tax" => true)
      assert_equal ["calculated", 27_000], q["tax"].values_at("status", "amount_cents")
      assert_equal 399_800 + 149_000 + 50_000 + 27_000, q["total_cents"]
      assert_equal 1, $tax_inputs.size
      refute_includes $tax_inputs.first.to_json, "Anna"
      refute_includes $tax_inputs.first.to_json, "Fő utca"
      quote(token, "want_tax" => true)
      assert_equal 1, $tax_inputs.size, "tax result is cached"
      # COD rule: zip not on the allow list
      bad = quote(token, "address" => { "country" => "HU", "city" => "Győr", "zip" => "9021", "address1" => "X 1" })
      assert_equal [false, ["zip_not_allowed"]], bad["eligibility"].values_at("cod_allowed", "reasons")
      s, e, = order(token, sid, bad["total_cents"], "address" => { "country" => "HU", "city" => "Győr", "zip" => "9021", "address1" => "X utca 1" })
      assert_equal [422, "not_eligible", false], [s, e["error"]["code"], e["eligibility"]["cod_allowed"]], e.inspect
      assert_equal "blocked", CodForm::Session.find_by(public_id: sid).status
      # order first: no OTP needed before the order; the response asks for it afterwards
      s, o, = order(token, sid, q["total_cents"], "idempotency_key" => "#{sid}:2")
      assert_equal 201, s, o.inspect + LOG.string
      assert_equal({ "pending" => true }, o["otp"])
      NetworkServices::VerifyPreOrderOtpService.code = "1234"
      s, v, = api("POST", "otp/verify", { "token" => token, "phone" => "301234567", "country" => "HU", "code" => "1234" })
      assert_equal 200, s, v.inspect + LOG.string
      assert_equal ["✅ COD-Verified"], ShopifyServices::OrderTagPostService.calls.last[2..]
    ensure
      CodForm::CatalogService.singleton_class.class_eval { alias_method :admin_query, :orig_admin_query } if CodForm::CatalogService.respond_to?(:orig_admin_query)
    end

    def test_automatic_discounts_are_honoured_from_the_opening_quote
      CodForm::CatalogService.singleton_class.class_eval do
        alias_method :orig_admin_query, :admin_query
        define_method(:admin_query) do |shop, query, variables = {}|
          if query.include?("platformDiscounts")
            $auto_inputs << variables["input"]
            # Buy one get one: the second unit of the first line is free
            items = variables["input"]["lineItems"].each_with_index.map do |l, i|
              price = CATALOG[l["variantId"].split("/").last]["price"].to_f
              { "discountedTotalSet" => { "presentmentMoney" => { "amount" => format("%.2f", price * l["quantity"] - (i.zero? ? price : 0)) } } }
            end
            [{ "draftOrderCalculate" => { "calculatedDraftOrder" => { "lineItems" => items, "platformDiscounts" => [
              { "title" => "Buy1Get1-New", "automaticDiscount" => true, "totalAmountPriceSet" => { "presentmentMoney" => { "amount" => "1999.00" } } },
              { "title" => "A code", "automaticDiscount" => false, "totalAmountPriceSet" => { "presentmentMoney" => { "amount" => "5.00" } } }
            ] }, "userErrors" => [] } }, []]
          else
            orig_admin_query(shop, query, variables)
          end
        end
      end
      $auto_inputs = []
      Rails.cache.delete(CodForm::QuoteService.automatic_seen_key(@shop))
      # a product-page open on a shop with no known discounts costs no Shopify calculation
      _, plain, = open_session
      assert_equal 0, $auto_inputs.size
      assert_empty plain["quote"]["discounts"].select { |d| d["kind"] == "automatic" }
      # a cart whose line price is below the catalog price: the opening quote asks Shopify
      _, b, = open_session("source" => "cart", "items" => [{ "variant_id" => "44111", "quantity" => 2, "properties" => {}, "cart_line_price_cents" => 199_900 }])
      assert_equal true, $auto_inputs.first["acceptAutomaticDiscounts"]
      assert_equal %w[acceptAutomaticDiscounts lineItems presentmentCurrencyCode shippingAddress], $auto_inputs.first.keys.sort
      assert_equal [{ "kind" => "automatic", "title" => "Buy1Get1-New", "amount_cents" => 199_900 }], b["quote"]["discounts"].select { |d| d["kind"] == "automatic" }
      assert_equal plain["quote"]["merchandise_total_cents"] - 199_900, b["quote"]["merchandise_total_cents"]
      assert_equal [199_900, 199_900], b["quote"]["lines"].first.values_at("discount_cents", "line_total_cents")
      sid = b["session_id"]; token = old_token(sid)
      # a quote with other selections (shipping rate, address) keeps the discount
      q = quote(token)
      assert_equal 199_900, q["discounts"].find { |d| d["kind"] == "automatic" }["amount_cents"]
      assert_equal q["merchandise_total_cents"] + q["shipping_cents"] + q["cod_fee"]["amount_cents"], q["total_cents"]
      # the order is created with the discount as an explicit line discount, Shopify adds nothing
      s, o, = order(token, sid, q["total_cents"])
      assert_equal 201, s, o.inspect + LOG.string
      draft = ShopifyServices::CodOrderCreateService.calls.last[1][:form_context][:draft_input]
      assert_equal false, draft["acceptAutomaticDiscounts"]
      assert_equal({ "valueType" => "FIXED_AMOUNT", "value" => 999.5, "title" => "Buy1Get1-New", "description" => "Buy1Get1-New" }, draft["lineItems"].first["appliedDiscount"])
      # from now on the shop is known to run automatic discounts: product-page opens ask too
      _, again, = open_session
      assert_equal 199_900, again["quote"]["discounts"].find { |d| d["kind"] == "automatic" }["amount_cents"]
    ensure
      Rails.cache.delete(CodForm::QuoteService.automatic_seen_key(@shop)) if @shop
      CodForm::CatalogService.singleton_class.class_eval { alias_method :admin_query, :orig_admin_query } if CodForm::CatalogService.respond_to?(:orig_admin_query)
    end

    def test_config_gives_the_form_before_a_session_exists
      CodForm::CatalogService.queries.clear
      s, c, h = api("GET", "config?country=HU&locale=hu")
      assert_equal 200, s, c.inspect + LOG.string
      assert_empty CodForm::CatalogService.queries, "no Shopify call"
      assert_equal %w[max-age=60 public], h["cache-control"].split(", ").sort
      _, b, = open_session
      assert_equal b["form"], c["form"]
      assert_equal b["country_schema"], c["country_schema"]
      assert_equal b["countries"], c["countries"]
      assert_equal ["hu", false], c.values_at("locale", "rtl")
      refute c.key?("token")
      # a country the form is not enabled for, or a disabled module: nothing to draw early
      CodForm::ShopConfig.rows.first.update_columns(general: { "countries" => ["HU"] })
      _, none, = api("GET", "config?country=DE")
      assert_nil none["form"]
      s, = api("GET", "config?country=HU", nil, origin: "https://evil.com")
      assert_equal 403, s
    end

    def test_non_shopify_province_goes_to_address2
      out = CodForm::OrderService.shopify_address("country" => "PK", "province" => "PB", "city" => "Lahore", "address2" => "")
      assert_equal ["", "Punjab"], out.values_at("province", "address2")
      out = CodForm::OrderService.shopify_address("country" => "CO", "province" => "ANT", "city" => "Medellín")
      assert_equal "ANT", out["province"]
      out = CodForm::OrderService.shopify_address("country" => "DE", "province" => "BY")
      assert_equal "BY", out["province"]
      # Peru: Shopify's code keeps its "PE-" prefix through DraftOrderBuilder's strip
      assert_equal "PE-LIM", CodForm::OrderService.shopify_address("country" => "PE", "province" => "PE-LIM")["province"]
      input = CodForm::Engine::DraftOrderBuilder.build(
        quote: { "_draft" => { "currency" => "PEN", "lines" => [] } }, contact: {},
        address: CodForm::OrderService.draft_address("country" => "PE", "province" => "PE-LIM", "city" => "Huacho", "address1" => "x"), meta: {}
      )
      assert_equal "PE-LIM", input["shippingAddress"]["provinceCode"]
      assert_equal "ANT", CodForm::OrderService.draft_address("country" => "CO", "province" => "ANT")["province"]
    end
  end

  require "rack/attack"
  class RackAttackTest < Minitest::Test
    def test_initializer_loads_and_throttles
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      load File.join(ROOT, "config/initializers/rack_attack.rb")
      app = Rack::Attack.new(->(_env) { [200, {}, ["ok"]] })
      call = lambda do |method, path, ip = "198.51.100.7"|
        app.call(Rack::MockRequest.env_for(path, method: method, "REMOTE_ADDR" => ip, input: "{}", "CONTENT_TYPE" => "text/plain"))
      end
      names = Rack::Attack.throttles.keys
      %w[codf/session/ip codf/quote/ip codf/orders/ip codf/orders/shop codf/otp/ip codf/events/ip cod_orders/ip req/ip].each { |n| assert_includes names, n }
      statuses = 12.times.map { call.("POST", "/api/form/otp/send?shop=a.myshopify.com").first }
      assert_equal [200] * 10 + [429] * 2, statuses
      status, headers, body = call.("POST", "/api/form/otp/verify?shop=a.myshopify.com")
      assert_equal 429, status
      parsed = JSON.parse(body.join)
      assert_equal [false, "rate_limited"], [parsed["ok"], parsed["error"]["code"]]
      assert parsed["error"]["retry_after"].between?(1, 600)
      assert_equal parsed["error"]["retry_after"].to_s, headers["retry-after"]
      assert_match(/json/, headers["content-type"])
      # another ip, another bucket
      assert_equal 200, call.("POST", "/api/form/otp/send?shop=a.myshopify.com", "198.51.100.8").first
      assert_equal 200, call.("POST", "/api/form/quote?shop=a.myshopify.com").first
      # legacy endpoint: 30 per 10 minutes, default plain-text body
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
      results = 31.times.map { |i| sleep 0.13 if i % 39 == 38; call.("POST", "/api/cod_orders", "198.51.100.#{20 + i / 40}") }
      assert_equal 429, results.last.first
      assert_equal "Retry later\n", results.last[2].join
      assert_equal "codf/quote/ip", Rack::Attack.cod_form_bucket(Rack::Attack::Request.new(Rack::MockRequest.env_for("/api/form/geo/PK", method: "GET")))
      assert_equal "codf/quote/ip", Rack::Attack.cod_form_bucket(Rack::Attack::Request.new(Rack::MockRequest.env_for("/api/form/config", method: "GET")))
      assert_nil Rack::Attack.cod_form_bucket(Rack::Attack::Request.new(Rack::MockRequest.env_for("/api/cod_orders", method: "POST")))
    end
  end
end
