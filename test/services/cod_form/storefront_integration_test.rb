# Cross-stream integration checks of the storefront API (docs/cod-form/notes/integration.md).
#
# Same in-memory harness as storefront_api_smoke_test.rb (real controllers, services and
# engines; fake models and Shopify). Standalone, NOT through `rails test`:
#
#   ruby test/services/cod_form/storefront_integration_test.rb
#
# Covers what the integration pass changed: the resolved province mode (server and browser agree
# on whether the field exists), the order response the browser pixels need, the order note, the
# test-order checklist stamp, post-order work for partial hand-off orders, the prepaid discount
# on a plain "Pay online" hand-off, and a create whose outcome is unknown.
if defined?(::Rails::Application)
  warn "[cod_form] storefront_integration_test.rb is a standalone script; skipped inside the Rails test run"
else
  require_relative "support/storefront_smoke_harness"
  require "minitest/autorun"

  class Shop
    attr_accessor :rules

    def partial_rule_sets
      FakeRelation.new(nil, (rules || []).map { |r| IntegrationRuleRow.new(r) })
    end
  end

  class IntegrationRuleRow
    def initialize(hash); @hash = hash.stringify_keys; end
    def [](key); @hash[key.to_s]; end
    def as_json(*); @hash; end
  end

  unless defined?(ShopifyAPI)
    module ShopifyAPI
      class Order
        def self.find(id)
          OpenStruct.new(id: id, name: "#77", order_number: 77, total_price: "5988.00", currency: "HUF", order_status_url: "https://brand.hu/orders/s")
        end
      end
    end
  end

  class StorefrontIntegrationTest < Minitest::Test
    NOTE = "Ring the bell twice please"

    def setup
      @shop = seed!
      Province.reset!
      CodForm::PostOrderJob.jobs.clear
      LOG.truncate(0)
      LOG.rewind
    end

    def open_session(extra = {})
      api("POST", "session", { "source" => "product", "locale" => "hu", "country" => "HU", "items" => [{ "variant_id" => "44111", "quantity" => 2 }],
                               "client_id" => "cid-1", "device" => "mobile" }.merge(extra))
    end

    def old_token(sid)
      CodForm::Engine::SessionToken.issue(secret: Api::Form::BaseController.token_secret, shop_id: @shop.id, session_id: sid,
                                          issued_at: 60.seconds.ago.to_i, test: CodForm::Session.find_by(public_id: sid).is_test)
    end

    def base(token, extra = {})
      { "token" => token, "items" => [{ "variant_id" => "44111", "quantity" => 2 }], "shipping_rate_id" => 1,
        "contact" => { "first_name" => "Anna", "phone" => "301234567", "email" => "" },
        "address" => { "country" => "HU", "city" => "Budapest", "zip" => "1051", "address1" => "Fő utca 1" } }.merge(extra)
    end

    def quote(token, extra = {})
      status, body, = api("POST", "quote", base(token, extra))
      assert_equal 200, status, body.inspect + LOG.string
      body["quote"]
    end

    def order(token, sid, total, extra = {})
      api("POST", "orders", base(token, { "idempotency_key" => "#{sid}:1", "payment_option_id" => "cod", "expected_total_cents" => total, "elapsed_ms" => 9000 }.merge(extra)))
    end

    # ---- item 2: province -------------------------------------------------------------------

    def test_province_is_hidden_without_a_list_and_required_with_one
      CodForm::ShopConfig.rows.first.update_columns(general: { "countries" => %w[HU SA] })
      CodForm::ShippingRate.create!(shop_id: @shop.id, name: "KSA", price_cents: 100_000, conditions: { "countries" => ["SA"] })
      sa = { "address" => { "country" => "SA", "city" => "Riyadh", "address1" => "King Fahd Road 1" },
             "contact" => { "first_name" => "Anna", "phone" => "501234567" }, "shipping_rate_id" => 2 }

      # Saudi Arabia is "auto" in countries.json; there is no dataset and no `provinces` row.
      _, b, = open_session("country" => "SA")
      assert_equal %w[hidden auto], b["country_schema"]["address"]["province"].values_at("mode", "declared_mode"), b.inspect + LOG.string
      status, geo, = api("GET", "geo/sa")
      assert_equal [200, [], "hidden"], [status, geo["provinces"], geo["schema"]["address"]["province"]["mode"]]
      sid = b["session_id"]
      token = old_token(sid)
      q = quote(token, sa)
      status, o, = order(token, sid, q["total_cents"], sa)
      assert_equal 201, status, o.inspect + LOG.string # no province sent, none required

      # With a province list the same country gets a select, and the default form requires it.
      Province.create!(country_code: "SA", province_code: "01", province_name: "Riyadh", country_name: "Saudi Arabia")
      Rails.cache.clear
      _, b, = open_session("country" => "SA", "client_id" => "cid-2")
      assert_equal "select", b["country_schema"]["address"]["province"]["mode"]
      status, geo, = api("GET", "geo/sa")
      assert_equal [[{ "code" => "01", "name" => "Riyadh" }], "select"], [geo["provinces"], geo["schema"]["address"]["province"]["mode"]]
      sid = b["session_id"]
      token = old_token(sid)
      q = quote(token, sa)
      status, e, = order(token, sid, q["total_cents"], sa)
      assert_equal [422, "validation_failed", { "province" => "error_province" }], [status, e["error"]["code"], e["error"]["fields"]]
      with = sa.merge("address" => sa["address"].merge("province" => "01"))
      q = quote(token, with)
      status, o, = order(token, sid, q["total_cents"], with.merge("idempotency_key" => "#{sid}:2"))
      assert_equal 201, status, o.inspect + LOG.string

      # A dataset country: select from the file; a declared-hidden one stays hidden.
      _, geo, = api("GET", "geo/pk")
      assert_equal "select", geo["schema"]["address"]["province"]["mode"]
      _, geo, = api("GET", "geo/hu")
      assert_equal "hidden", geo["schema"]["address"]["province"]["mode"]
    end

    # ---- items 4, 8, 11 and the session contract ------------------------------------------------

    def test_order_response_event_ids_note_and_session_features
      _, b, = open_session
      assert_equal true, b["features"]["respect_consent"]
      sid = b["session_id"]
      token = old_token(sid)
      q = quote(token)
      status, o, = order(token, sid, q["total_cents"], "fields" => { "note" => NOTE, "gst_number" => "" })
      assert_equal 201, status, o.inspect + LOG.string
      map = CodForm::Tracking::EventMap
      assert_equal "order_6123456789_purchase", o["events"]["purchase_event_id"]
      assert_equal "order_6123456789_lead", o["events"]["lead_event_id"]
      # exactly the ids the server-side dispatcher derives for the same order
      assert_equal map.event_id(moment: "purchase", order_id: "6123456789", purchase_event: "purchase"), o["events"]["purchase_event_id"]
      assert_equal map.event_id(moment: "purchase", order_id: "6123456789", purchase_event: "lead"), o["events"]["lead_event_id"]

      row = CodForm::Session.find_by(public_id: sid)
      assert_equal NOTE, row.custom_fields["note"]
      refute row.custom_fields.key?("gst_number")
      assert_equal false, row.custom_fields["marketing_consent"]
      refute_includes LOG.string, NOTE
      # a real order never touches the test-order checklist step
      assert_nil CodForm::ShopConfig.rows.first.setup_state["test_order_at"]

      # the status replay carries the same ids
      status, replay, = api("POST", "orders/status", { "token" => token })
      assert_equal [200, o["events"]], [status, replay["events"]]

      CodForm::ShopConfig.rows.first.update_columns(general: { "countries" => ["HU"], "consent" => { "respect_customer_privacy" => false } })
      _, b, = open_session("client_id" => "cid-3")
      assert_equal false, b["features"]["respect_consent"]
    end

    def test_pixel_config_keeps_the_keys_the_browser_needs
      resolver = CodForm::Tracking::PixelResolver.singleton_class
      resolver.send(:alias_method, :orig_for, :for)
      resolver.send(:define_method, :for) do |_shop, product_ids:, collection_ids:|
        [{ "platform" => "tiktok", "pixel_id" => "C0DE", "access_token" => "LEAK", "targeting" => {},
           "config" => { "browser" => true, "server" => true, "purchase_event" => "lead", "tiktok_event" => "place_order",
                         "events" => { "form_open" => true, "purchase" => true }, "test_event_code" => "T" } }]
      end
      _, b, = open_session
      assert_equal [{ "platform" => "tiktok", "pixel_id" => "C0DE", "targeting" => {},
                      "config" => { "browser" => true, "purchase_event" => "lead", "tiktok_event" => "place_order",
                                    "events" => { "form_open" => true, "purchase" => true } } }], b["pixels"]
      refute_includes b.to_json, "LEAK"
    ensure
      resolver.send(:alias_method, :for, :orig_for)
    end

    def test_test_order_completes_the_setup_checklist_step
      _, b, = open_session("preview_token" => "a" * 32)
      assert_equal true, b["test"]
      sid = b["session_id"]
      token = old_token(sid)
      q = quote(token)
      status, o, = order(token, sid, q["total_cents"])
      assert_equal [201, true], [status, o["test"]], o.inspect + LOG.string
      config = CodForm::ShopConfig.rows.first
      stamp = config.setup_state["test_order_at"]
      assert_match(/\A\d{4}-\d{2}-\d{2}T/, stamp.to_s)
      usage = CodForm::OrderUsage.rows.first
      assert_equal [0, 1], [usage.orders_count, usage.test_orders_count]
      # the stamp is written once
      _, b2, = open_session("preview_token" => "a" * 32, "client_id" => "cid-4")
      t2 = old_token(b2["session_id"])
      order(t2, b2["session_id"], quote(t2)["total_cents"])
      assert_equal stamp, config.setup_state["test_order_at"]
    end

    # ---- item 5: partial hand-off orders get the post-order work ---------------------------------

    def test_partial_handoff_order_enqueues_post_order_job
      @shop.setting["partial_payment_enabled"] = true
      @shop.rules = [{ "id" => 17, "is_enabled" => true, "amount_type" => "fixed", "amount" => "1000.0", "position" => 0, "product_scope" => "all" }]
      _, b, = open_session
      sid = b["session_id"]
      token = old_token(sid)
      quote(token)
      status, h, = api("POST", "handoff", base(token, "kind" => "partial", "payment_option_id" => "rule_17", "reason" => "buyer_choice"))
      assert_equal 200, status, h.inspect + LOG.string
      row = CodForm::Session.find_by(public_id: sid)
      params = { "id" => 9001, "name" => "#2001", "total_price" => "5988.00", "currency" => "HUF", "source_name" => "web", "note" => NOTE,
                 "note_attributes" => [{ "name" => "_codkFormSessionId", "value" => sid }] }
      CodForm::OrderWebhookHook.after(@shop, params)
      assert_equal ["ordered", "9001"], [row.status, row.order_id]
      assert_equal [[row.id, "handoff"]], CodForm::PostOrderJob.jobs
      assert_equal NOTE, row.custom_fields["note"]
      assert_equal [1, 1], CodForm::OrderUsage.rows.first.attrs.values_at("orders_count", "partial_orders_count")
      CodForm::OrderWebhookHook.after(@shop, params) # webhook retry
      assert_equal 1, CodForm::PostOrderJob.jobs.size
      refute_includes LOG.string, NOTE
    end

    def test_prepaid_handoff_order_is_not_counted_and_gets_no_post_order_job
      _, b, = open_session
      sid = b["session_id"]
      token = old_token(sid)
      quote(token)
      status, h, = api("POST", "handoff", base(token, "kind" => "prepaid", "reason" => "buyer_choice"))
      assert_equal 200, status, h.inspect + LOG.string
      assert_nil h["discount_code"]
      row = CodForm::Session.find_by(public_id: sid)
      assert_nil row.partial_rule_set_id
      CodForm::OrderWebhookHook.after(@shop, { "id" => 9002, "name" => "#2002", "total_price" => "5988.00", "currency" => "HUF", "source_name" => "web",
                                               "note_attributes" => [{ "name" => "_codkFormSessionId", "value" => sid }] })
      assert_equal ["ordered", "9002"], [row.status, row.order_id]
      assert_empty CodForm::PostOrderJob.jobs
      assert_empty CodForm::OrderUsage.rows
      assert_equal "cf_prepaid_order", CodForm::FunnelLogger.events.last[:type]
    end

    # ---- item 6: PRE-2 on a plain "Pay online" hand-off ------------------------------------------

    def test_pay_online_gets_the_discount_of_a_matching_prepaid_rule
      @shop.setting["partial_payment_enabled"] = true
      @shop.rules = [{ "id" => 18, "is_enabled" => true, "amount_type" => "percentage", "amount" => "100", "position" => 0, "product_scope" => "all",
                       "discount_code" => "PREPAID10", "discount_type" => "percentage", "discount_value" => "10" }]
      _, b, = open_session
      sid = b["session_id"]
      token = old_token(sid)
      q = quote(token)
      option = q["payment_options"]["options"].find { |o| o["id"] == "rule_18" }
      assert_equal "prepaid", option["kind"]
      assert option["discount_cents"].positive?
      status, h, = api("POST", "handoff", base(token, "kind" => "prepaid", "reason" => "blocked")) # no payment_option_id
      assert_equal 200, status, h.inspect + LOG.string
      assert_equal "PREPAID10", h["discount_code"]
      assert_match(/\AorderLevel:[\d.]+\|PREPAID10\z/, h["cart_attributes"]["_codkDiscounts"])
      assert_equal [true, "percentage", "100"], h["cart_attributes"].values_at("_partialPaymentProduct", "_codkAmountType", "_codkAmountValue")
      assert_equal ["handoff_prepaid", 18], CodForm::Session.find_by(public_id: sid).attrs.values_at("status", "partial_rule_set_id")
    end

    def test_pay_online_without_a_discounted_prepaid_rule_is_a_plain_handoff
      @shop.setting["partial_payment_enabled"] = true
      @shop.rules = [{ "id" => 19, "is_enabled" => true, "amount_type" => "percentage", "amount" => "100", "position" => 0, "product_scope" => "all" }]
      _, b, = open_session
      sid = b["session_id"]
      token = old_token(sid)
      quote(token)
      status, h, = api("POST", "handoff", base(token, "kind" => "prepaid", "reason" => "blocked"))
      assert_equal 200, status, h.inspect + LOG.string
      assert_nil h["discount_code"]
      assert_equal %w[_codkFormId _codkFormSessionId], h["cart_attributes"].keys.sort
      assert_nil CodForm::Session.find_by(public_id: sid).partial_rule_set_id
    end

    # ---- item 6: a create whose outcome is unknown must not allow a second order ------------------

    def test_unknown_create_outcome_keeps_the_claim_until_the_webhook_reports_the_order
      _, b, = open_session
      sid = b["session_id"]
      token = old_token(sid)
      q = quote(token)
      ShopifyServices::CodOrderCreateService.result = { error: "Failed to create order from draft order", code: "complete_failed", outcome_unknown: true }
      status, e, = order(token, sid, q["total_cents"])
      assert_equal [409, "already_processing", 1500], [status, e["error"]["code"], e["poll_after_ms"]]
      row = CodForm::Session.find_by(public_id: sid)
      assert_equal "ordering", row.status, "the claim is kept: a retry cannot create a second order"
      status, e, = order(token, sid, q["total_cents"])
      assert_equal [409, "already_processing"], [status, e["error"]["code"]]
      assert_equal 1, ShopifyServices::CodOrderCreateService.calls.size
      status, st, = api("POST", "orders/status", { "token" => token })
      assert_equal [202, "processing"], [status, st["status"]]

      # the orders/create webhook saw the order (CodForm::OrderWebhookHook#remember_order_id)
      row.update_columns(tracking: row.tracking.merge("webhook_order_id" => "777"))
      status, st, = api("POST", "orders/status", { "token" => token })
      assert_equal [200, "777", "order_777_lead"], [status, st["order"]["id"], st["events"]["lead_event_id"]], st.inspect + LOG.string
      assert_equal ["ordered", "777"], [row.status, row.order_id]
      assert_equal 1, CodForm::OrderUsage.rows.first.orders_count
      assert_equal [[row.id]], CodForm::PostOrderJob.jobs
      status, again, = api("POST", "orders/status", { "token" => token })
      assert_equal [200, st], [status, again]
      assert_equal 1, CodForm::PostOrderJob.jobs.size
      assert_equal 1, CodForm::OrderUsage.rows.first.orders_count
    end

    def test_known_create_failure_releases_the_session
      _, b, = open_session
      sid = b["session_id"]
      token = old_token(sid)
      q = quote(token)
      ShopifyServices::CodOrderCreateService.result = { error: "Failed to create order from draft order", code: "complete_failed" }
      status, e, = order(token, sid, q["total_cents"])
      assert_equal [502, "order_failed", "error_order_failed"], [status, e["error"]["code"], e["error"]["message_key"]]
      assert_equal "open", CodForm::Session.find_by(public_id: sid).status
    end

    def test_order_without_readable_details_is_still_a_success
      _, b, = open_session
      sid = b["session_id"]
      token = old_token(sid)
      q = quote(token)
      # what CodOrderCreateService answers on the form path when Order.find failed after the create
      ShopifyServices::CodOrderCreateService.result = lambda do |kw|
        { success: true, order_id: 6123456790, order_number: nil, order_name: nil, total_price: nil, currency_code: nil, order_status_url: nil,
          draft_total_cents: kw[:form_context][:expected_total_cents], draft_order_id: "gid://shopify/DraftOrder/2" }
      end
      status, o, = order(token, sid, q["total_cents"])
      assert_equal [201, "6123456790", "HUF"], [status, o["order"]["id"], o["order"]["currency"]], o.inspect + LOG.string
      assert_equal "ordered", CodForm::Session.find_by(public_id: sid).status
    end

    # ---- item 12: contract details ---------------------------------------------------------------

    def test_error_message_keys_are_storefront_text_keys
      _, b, = open_session
      sid = b["session_id"]
      token = old_token(sid)
      # (No shipping rate is no longer an error: the order ships free, see ShippingRates::FREE_RATE.)
      status, e, = api("POST", "upsell_accept", { "token" => token, "offer_id" => 1, "accept" => true })
      assert_equal [410, "upsell_expired", "error_generic"], [status, e["error"]["code"], e["error"]["message_key"]]
    end

    def test_session_fallbacks_are_200_without_a_token
      CodForm::GlobalSetting.current.update_columns(kill_switch: true)
      status, b, = open_session
      assert_equal [200, true, "kill_switch", nil], [status, b["ok"], b["fallback"], b["token"]]
      CodForm::GlobalSetting.current.update_columns(kill_switch: false)
      Rails.cache.clear
      status, b, = open_session("items" => [])
      assert_equal [200, "config_error", nil], [status, b["fallback"], b["token"]]
      status, b, = open_session("country" => "DE")
      assert_equal [200, "not_eligible_country"], [status, b["fallback"]]
    end

    def test_saved_addresses_are_reduced_to_form_fields
      rows = [
        { "id" => 9, "first_name" => "Anna", "last_name" => "Kiss", "address1" => "12 MG Road, Indiranagar", "address2" => "", "city" => "Bengaluru",
          "province" => "Karnataka", "province_code" => "KA", "country" => "India", "country_code" => "IN", "zip" => "560038", "phone" => "+919812345678",
          "latitude" => "12.9", "shopify_id" => "123", "source" => "shopify" },
        { "first_name" => "Anna", "address1" => "1 Main Street", "city" => "Lahore", "country_code" => "PK", "zip" => "54000" }
      ]
      out = CodForm::OtpService.saved_addresses(rows, "IN")
      assert_equal [{ "first_name" => "Anna", "last_name" => "Kiss", "address1" => "12 MG Road, Indiranagar", "city" => "Bengaluru",
                      "zip" => "560038", "province" => "KA" }], out
      assert_equal [], CodForm::OtpService.saved_addresses(nil, "IN")
      assert_equal 1, CodForm::OtpService.saved_addresses(rows.first, "in").size
    end
  end
end
