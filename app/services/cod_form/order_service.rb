# frozen_string_literal: true

module CodForm
  # Idempotent order submit of the COD Form (ARCHITECTURE.md F.2, D.6, D.7).
  #
  #   result = CodForm::OrderService.call(shop:, config:, session:, params:, request_meta:)
  #   result.status  # 201 created | 200 replay | 202 processing
  #   result.body    # D.6 body (string keys)
  #
  # Every rejection is a CodForm::Errors::ApiError. Nothing sent by the browser is used as a
  # price: the order is built from a fresh server quote (ORD-2).
  class OrderService
    Result = Struct.new(:status, :body)

    # A session left in 'ordering' this long belongs to a request that died; it may be claimed again.
    STALE_ORDERING_SECONDS = 120
    ASYNC_WAIT_SECONDS = 8
    ASYNC_POLL_SECONDS = 0.25
    POLL_AFTER_MS = 1500
    RESPONSE_KEY = "order_response"
    HONEYPOT_FIELD = "codkf_company_url"
    SUBMIT_KEY = "submit"
    TRACKING_KEYS = %w[fbp fbc ttp ttclid ga_client_id ga_session_id scid sccid epik page_url user_agent].freeze
    BLOCKED_CODES = %w[blocked limit_reached not_eligible].freeze
    STOCK_PATTERN = /stock|inventory|unavailable|sold out|not available/i.freeze

    class << self
      def call(shop:, config:, session:, params:, request_meta:)
        new(shop: shop, config: config, session: session, params: params, request_meta: request_meta).call
      end

      # D.7 — the state of a submit (used by the polling client and by replays).
      def status(session:)
        session.reload
        return Result.new(200, stored_response(session) || minimal_response(session)) if session.order_id.present?

        if session.status == CodForm::Session::STATUS_ORDERING
          return adopt_from_webhook(session) || Result.new(202, processing_body)
        end

        raise CodForm::Errors.build("order_failed", extra: { "order_error" => session.order_error.to_s.presence || "not_submitted" })
      end

      # A submit whose outcome was unknown (see handle_create_failure!) or whose request died:
      # when the orders/create webhook has already reported the order of this session, answer
      # with it instead of "processing". nil when there is nothing to adopt (yet).
      def adopt_from_webhook(session)
        order_id = session.tracking.is_a?(Hash) ? session.tracking["webhook_order_id"].to_s : ""
        return nil unless order_id.match?(/\A\d+\z/)

        shop = Shop.find(session.shop_id)
        new(shop: shop, config: CodForm::ShopConfig.for(shop), session: session, params: {}, request_meta: {})
          .adopt_webhook_order
      rescue CodForm::Errors::ApiError
        nil
      end

      # Background half of an async submit (ORD-9), run by CodForm::CreateOrderJob.
      def finish_async(session_id)
        session = CodForm::Session.find_by(id: session_id)
        return if session.nil? || session.order_id.present? || session.status != CodForm::Session::STATUS_ORDERING

        shop = Shop.find(session.shop_id)
        snapshot = session.cart_snapshot.is_a?(Hash) ? session.cart_snapshot[SUBMIT_KEY] : nil
        return unless snapshot.is_a?(Hash)

        service = new(shop: shop, config: CodForm::ShopConfig.for(shop), session: session,
                      params: snapshot["params"].is_a?(Hash) ? snapshot["params"] : {},
                      request_meta: snapshot["request_meta"].is_a?(Hash) ? snapshot["request_meta"] : {})
        service.finish_in_background
      end

      def stored_response(session)
        snapshot = session.quote_snapshot.is_a?(Hash) ? session.quote_snapshot : {}
        snapshot[RESPONSE_KEY].is_a?(Hash) ? snapshot[RESPONSE_KEY] : nil
      end

      def processing_body
        { "ok" => true, "status" => "processing", "poll_after_ms" => POLL_AFTER_MS }
      end

      # D.6 body rebuilt from the session row alone (replay of an order whose full response
      # was not stored, or whose response could not be built).
      def minimal_response(session, order = nil)
        order ||= {
          "id" => session.order_id.to_s, "name" => session.order_name, "number" => session.order_name.to_s.gsub(/\D/, "").to_i,
          "total_cents" => session.order_total_cents, "currency" => session.currency, "status_url" => nil
        }
        {
          "ok" => true, "order" => order,
          "thank_you" => { "type" => "message", "url" => nil, "message" => nil, "whatsapp_url" => nil },
          "upsell" => nil,
          "events" => event_ids(order["id"]).merge("value_cents" => order["total_cents"],
                                                   "currency" => order["currency"], "content_ids" => [], "num_items" => 0),
          "web_pixel" => { "orderId" => order["id"], "totalPrice" => CodForm::Engine::Money.to_decimal_string(order["total_cents"].to_i),
                           "currencyCode" => order["currency"], "email" => "", "attribution" => {} },
          "test" => session.is_test ? true : false
        }
      end

      # I.2: the ids the browser pixels must send so that they deduplicate against the server
      # events of CodForm::Tracking::ServerDispatchJob. Both come from the one table
      # (CodForm::Tracking::EventMap): a pixel configured with purchase_event "lead" uses
      # lead_event_id, every other pixel purchase_event_id.
      def event_ids(order_id)
        map = CodForm::Tracking::EventMap
        {
          "purchase_event_id" => map.event_id(moment: map::MOMENT_PURCHASE, order_id: order_id, purchase_event: "purchase"),
          "lead_event_id" => map.event_id(moment: map::MOMENT_PURCHASE, order_id: order_id, purchase_event: "lead")
        }
      end

      # The address handed to DraftOrderBuilder. For countries whose province list is not
      # Shopify's (dataset flag "shopify_provinces": false) no provinceCode is sent; the province
      # name is kept in address2 so the courier still sees it.
      def shopify_address(address)
        address = address.is_a?(Hash) ? address : {}
        dataset = CodForm::CatalogService.geo_dataset(address["country"])
        return address if dataset.nil? || dataset["shopify_provinces"] != false || address["province"].to_s.empty?

        entry = Array(dataset["provinces"]).find { |p| p["code"].to_s.casecmp?(address["province"].to_s) }
        name = entry ? entry["name"].to_s : address["province"].to_s
        address2 = address["address2"].to_s
        address2 = [address2, name].reject(&:empty?).join(", ") unless address2.downcase.include?(name.downcase)
        address.merge("province" => "", "address2" => address2[0, 255])
      end

      # shopify_address for CodForm::Engine::DraftOrderBuilder, which strips one leading
      # "<country>-" from the province. Shopify's own codes for Peru carry that prefix
      # ("PE-LIM"), so it is doubled here and survives the strip.
      def draft_address(address)
        shopify = shopify_address(address)
        country = shopify["country"].to_s.upcase
        province = shopify["province"].to_s
        return shopify if country.empty? || !province.upcase.start_with?("#{country}-")

        shopify.merge("province" => "#{country}-#{province}")
      end
    end

    def initialize(shop:, config:, session:, params:, request_meta:)
      @shop = shop
      @config = config
      @session = session
      @params = params.is_a?(Hash) ? params : {}
      @meta = request_meta.is_a?(Hash) ? request_meta.transform_keys(&:to_s) : {}
      @setting = shop.setting
    end

    def call
      key = idempotency_key!
      replay = replay_result
      return replay if replay

      adopted = claim!(key)
      return adopted if adopted

      finished = false
      failure_code = "order_failed"
      begin
        prepared = prepare
        if CodForm::GlobalSetting.current.async_orders
          enqueue_async(prepared)
          finished = true
          return wait_for_async
        end

        body = finish(prepared)
        finished = true
        Result.new(201, body)
      rescue CodForm::Errors::ApiError => e
        failure_code = e.code
        raise
      rescue StandardError => e
        log("failed", error: e.class.name)
        report(e)
        raise CodForm::Errors.build("order_failed")
      ensure
        release!(failure_code) unless finished || @keep_claim
      end
    end

    def finish_in_background
      finished = false
      failure_code = "order_failed"
      begin
        finish(prepare(background: true))
        finished = true
      rescue CodForm::Errors::ApiError => e
        failure_code = e.code
      rescue StandardError => e
        log("background_failed", error: e.class.name)
        report(e)
      ensure
        release!(failure_code) unless finished || @keep_claim
      end
    end

    private

    attr_reader :shop, :config, :session, :params, :setting

    # ---- step 1: compare-and-set ---------------------------------------------------------

    def idempotency_key!
      key = params["idempotency_key"].to_s
      unless key.length <= 80 && key.start_with?("#{session.public_id}:") && key.match?(/\A[0-9a-fA-F\-]+:\d{1,6}\z/)
        raise CodForm::Errors.build("invalid_request", fields: { "idempotency_key" => "error_generic" })
      end

      key
    end

    def replay_result
      return nil unless session.order_id.present?

      body = self.class.stored_response(session)
      Result.new(200, body || self.class.minimal_response(session))
    end

    # One SQL UPDATE decides who creates the order. Returns nil when this request won,
    # a Result when an order already exists; raises already_processing otherwise.
    def claim!(key)
      now = Time.current
      won = CodForm::Session
            .where(id: session.id, order_id: nil, status: CodForm::Session::ORDERABLE_STATUSES)
            .update_all(status: CodForm::Session::STATUS_ORDERING, idempotency_key: key, updated_at: now)
      return nil.tap { session.reload } if won == 1

      session.reload
      return replay_result if session.order_id.present?

      if session.status == CodForm::Session::STATUS_ORDERING && session.updated_at < now - STALE_ORDERING_SECONDS
        adopted = adopt_webhook_order
        return adopted if adopted

        taken = CodForm::Session
                .where(id: session.id, order_id: nil, status: CodForm::Session::STATUS_ORDERING)
                .where("updated_at < ?", now - STALE_ORDERING_SECONDS)
                .update_all(idempotency_key: key, updated_at: now)
        return nil.tap { session.reload } if taken == 1
      end

      raise CodForm::Errors.build("already_processing", extra: { "poll_after_ms" => POLL_AFTER_MS })
    end

    public

    # The earlier request died after Shopify created the order but before it was stored here.
    # The orders/create webhook left the order id on the session (OrderWebhookHook): use it
    # instead of creating a second order. Public for OrderService.adopt_from_webhook.
    def adopt_webhook_order
      order_id = session.tracking.is_a?(Hash) ? session.tracking["webhook_order_id"].to_s : ""
      return nil unless order_id.match?(/\A\d+\z/)

      shop.init_session
      order = ShopifyAPI::Order.find(order_id)
      total_cents = (order.total_price.to_d * 100).round.to_i
      body = self.class.minimal_response(
        session,
        "id" => order_id, "name" => order.name, "number" => order.order_number, "total_cents" => total_cents,
        "currency" => order.currency, "status_url" => (order.respond_to?(:order_status_url) ? order.order_status_url : nil)
      )
      # Compare-and-set: a status poll and a re-submit can get here at the same moment.
      adopted = CodForm::Session.where(id: session.id, order_id: nil).update_all(
        status: CodForm::Session::STATUS_ORDERED, order_id: order_id, order_name: order.name,
        order_total_cents: total_cents, ordered_at: Time.current, order_error: nil,
        quote_snapshot: (session.quote_snapshot.is_a?(Hash) ? session.quote_snapshot : {}).merge(RESPONSE_KEY => body),
        updated_at: Time.current
      )
      session.reload
      if adopted == 1
        log("adopted_webhook_order", order_id: order_id)
        after_adopted(body["order"])
      end
      Result.new(200, self.class.stored_response(session) || body)
    rescue StandardError => e
      log("adopt_failed", error: e.class.name)
      raise CodForm::Errors.build("already_processing", extra: { "poll_after_ms" => POLL_AFTER_MS })
    end

    private

    # Any failure after the claim puts the session back so the buyer can retry (ORD-7).
    def release!(code)
      status = BLOCKED_CODES.include?(code) ? CodForm::Session::STATUS_BLOCKED : CodForm::Session::STATUS_OPEN
      CodForm::Session
        .where(id: session.id, order_id: nil, status: CodForm::Session::STATUS_ORDERING)
        .update_all(status: status, order_error: code.to_s[0, 60], updated_at: Time.current)
    rescue StandardError => e
      log("release_failed", error: e.class.name)
    end

    # ---- steps 2-10: everything that can reject the submit -----------------------------------

    def prepare(background: false)
      form_config = published_form_config
      is_test = session.is_test ? true : false
      flags = CodForm::Gates.flags(shop, config: config)
      fraud = CodForm::QuoteService.fraud_settings(config)
      ip = @meta["ip"].to_s

      # 2. bot checks (not repeated in the background half: timing was checked on submit)
      unless background
        bot = CodForm::Engine::Fraud.check(
          fraud: fraud, entries: {}, counts: {}, contact: {}, ip: ip, cart: {}, is_test: is_test,
          timing: {
            "elapsed_ms" => numeric(params["elapsed_ms"]),
            "token_age_ms" => token_age_ms,
            "honeypot_value" => params[HONEYPOT_FIELD].to_s
          }
        )
        if bot["code"] == "bot_suspected"
          CodForm::FraudAdapter.record_rejection(shop: shop, session: session, reason: bot["reason"], stage: "order", ip: ip)
          raise CodForm::Errors.build("bot_suspected")
        end
      end

      # 6 (first half). fresh quote from fresh catalog data; also normalises contact and address
      built = CodForm::QuoteService.build(
        shop: shop, config: config, session: session, params: params, stage: "submit", ip: ip, force_tax: true
      )
      quote = built.quote
      address = built.address
      phone = built.phone
      contact = buyer_contact(phone)

      # 3. validation
      validate!(form_config, built, phone)

      # 4. fraud: block lists, velocity limits, max quantity
      unless background
        check = CodForm::FraudAdapter.check(
          shop: shop, config: config, contact: built.contact, ip: ip, cart: { "lines" => built.lines },
          timing: nil, is_test: is_test, flags: flags, fraud: fraud
        )
        unless check["ok"] == true
          CodForm::FraudAdapter.record_rejection(shop: shop, session: session, reason: check["reason"], stage: "order",
                                                 contact: built.contact, ip: ip)
          raise CodForm::Errors.build(check["code"] == "limit_reached" ? "limit_reached" : "blocked", message: check["message"])
        end
        unless is_test
          limit, period = CodForm::RateLimiter.default_limit("order_phone")
          unless CodForm::RateLimiter.hit!(CodForm::RateLimiter.order_key(shop.id, phone["digits"]), limit: limit, period: period)
            raise CodForm::Errors.build("rate_limited", retry_after: CodForm::RateLimiter.retry_after(period))
          end
        end
      end

      # 5. cap (test sessions skip it)
      raise CodForm::Errors.build("cap_reached") if !is_test && CodForm::CapService.state(shop)["state"] == "fallback"

      # 6 (second half). what the fresh quote says
      eligibility = quote["eligibility"] || {}
      unless eligibility["cod_allowed"] == true
        CodForm::FraudAdapter.record_rejection(
          shop: shop, session: session, reason: Array(eligibility["reasons"]).first.to_s.presence || "not_eligible",
          stage: "order", contact: built.contact, ip: ip
        )
        raise CodForm::Errors.build("not_eligible", message: eligibility["message"], message_key: eligibility["message_key"],
                                                    extra: { "eligibility" => eligibility })
      end
      raise CodForm::Errors.build("no_shipping_rate") if quote.dig("shipping", "none_available") == true
      if Array(quote["lines"]).any? { |l| l["available"] == false || (l["max_quantity"] && l["quantity"].to_i > l["max_quantity"].to_i) }
        raise CodForm::Errors.build("out_of_stock", fields: { "items" => "error_out_of_stock" })
      end
      if params["discount_code"].to_s.strip != "" && quote.dig("discount_code", "status") != "applied"
        raise CodForm::Errors.build("discount_invalid", message_key: quote.dig("discount_code", "message_key"),
                                                        extra: { "quote" => built.public_quote })
      end

      # 7. OTP
      verified = CodForm::QuoteService.otp_verified_for?(session, phone)
      bypassed = session.otp.is_a?(Hash) && session.otp["bypassed"] == true
      raise CodForm::Errors.build("otp_required") if otp_needed?(quote, built.general) && !verified && !bypassed

      # 8. payment option: partial / prepaid go through /api/form/handoff
      if quote["payment_options"].is_a?(Hash) && params["payment_option_id"].to_s != "cod"
        raise CodForm::Errors.build("invalid_request", fields: { "payment_option_id" => "error_generic" })
      end

      # 9 + 10. tax was recomputed inside the quote; the buyer must have seen this exact total
      expected = params["expected_total_cents"]
      unless expected.is_a?(Integer) && expected == quote["total_cents"]
        raise CodForm::Errors.build("total_changed", extra: { "quote" => built.public_quote })
      end

      { built: built, contact: contact, address: address, verified: verified, form_config: form_config }
    end

    def validate!(form_config, built, phone)
      values = {
        "contact" => hash(params["contact"]), "address" => built.address,
        "fields" => hash(params["fields"]), "custom_fields" => hash(params["custom_fields"])
      }
      result = CodForm::Engine::FormValidator.validate(config: form_config, schema: built.schema, values: values)
      fields = result["fields"].is_a?(Hash) ? result["fields"].dup : {}
      fields["phone"] ||= "error_phone" unless phone["valid"] == true
      fields["country"] ||= "error_required" if built.address["country"].empty?
      raise CodForm::Errors.build("validation_failed", fields: fields) unless fields.empty?
    end

    def otp_needed?(quote, general)
      return false if general.dig("otp", "mode").to_s == "order_first"

      quote["otp_required"] == true
    end

    def token_age_ms
      issued = numeric(@meta["token_issued_at"])
      issued ? ((Time.current.to_f - issued) * 1000).round : nil
    end

    # ---- steps 11-17 ---------------------------------------------------------------------------

    def finish(prepared)
      built = prepared[:built]
      quote = built.quote
      contact = prepared[:contact]
      address = prepared[:address]
      verified = prepared[:verified]
      form_config = prepared[:form_config]

      # 11. customer
      customer_gid = CodForm::CustomerResolver.call(
        shop, phone_e164: contact["phone_e164"], email: contact["email"],
        first_name: contact["first_name"], last_name: contact["last_name"]
      )

      # 12. create
      attribution = CampaignAttributionHelper.normalize(hash(session.attribution).merge(hash(params["attribution"])))
      draft_input = CodForm::Engine::DraftOrderBuilder.build(
        quote: quote, contact: contact, address: self.class.draft_address(address),
        meta: {
          "shop_tags" => [], "verified" => verified,
          "verification_tag" => setting&.verification_tag.presence || "✅ COD-Verified",
          "session_id" => session.public_id, "form_id" => session.cod_form_id, "is_test" => session.is_test ? true : false,
          "attribution" => attribution, "custom_fields" => custom_field_rows(form_config),
          "customer_gid" => customer_gid, "note_fields" => note_fields,
          "otp_phone_e164" => verified ? contact["phone_e164"] : nil, "country" => address["country"]
        }
      )
      tolerance = [2, Array(draft_input["lineItems"]).size].max
      # F.2: 12 s read time-out on the GraphQL calls of the create (see lib/cod_form_shopify_timeout.rb).
      created = CodFormShopifyTimeout.with do
        ShopifyServices::CodOrderCreateService.call(
          shop, {}, {}, {}, nil, nil, verified,
          form_context: { draft_input: draft_input,
                          expected_total_cents: quote["total_cents"], tolerance_cents: tolerance }
        )
      end
      handle_create_failure!(created, built) if created[:error]

      drift = created[:draft_total_cents] ? created[:draft_total_cents].to_i - quote["total_cents"].to_i : 0
      log("order_created", order_id: created[:order_id], total_drift_cents: drift, lines: Array(draft_input["lineItems"]).size)

      # 13. persist — from here on nothing may undo the order
      order = {
        "id" => created[:order_id].to_s, "name" => created[:order_name].to_s, "number" => created[:order_number],
        "total_cents" => created[:draft_total_cents] || quote["total_cents"], "currency" => built.currency,
        "status_url" => created[:order_status_url]
      }
      upsell = pick_upsell(built)
      body =
        begin
          build_response(order, built, contact, form_config, upsell, attribution, verified)
        rescue StandardError => e
          log("response_build_failed", order_id: order["id"], error: e.class.name)
          self.class.minimal_response(session, order.slice("id", "name", "number", "total_cents", "currency", "status_url"))
        end
      persist!(order, built, contact, address, attribution, upsell, body)

      # 14-16. best effort
      after_order(built, order)
      body
    end

    def handle_create_failure!(created, built)
      # The call that completes the draft raised (time-out, 5xx): Shopify may have created the
      # order anyway. The session stays in 'ordering' — it is NOT released — so a retry cannot
      # create a second order: the client polls; the orders/create webhook leaves the order id
      # on the session and `status` / the next submit adopt it; without an order the claim goes
      # stale after STALE_ORDERING_SECONDS and the buyer can submit again.
      if created[:outcome_unknown]
        @keep_claim = true
        log("create_outcome_unknown")
        raise CodForm::Errors.build("already_processing", extra: { "poll_after_ms" => POLL_AFTER_MS })
      end

      case created[:code].to_s
      when "total_changed"
        shopify_total = created[:draft_total_cents]
        log("total_changed", shopify_total_cents: shopify_total, quote_total_cents: built.quote["total_cents"])
        # Shopify's total wins (ORD-3). It is remembered for this exact cart + destination, so
        # the buyer's confirmation of the new total is accepted by the next quote and submit.
        quote = CodForm::QuoteService.confirm_total!(session, built.quote, built.address, shopify_total)
        raise CodForm::Errors.build("total_changed", extra: { "quote" => quote })
      when "draft_user_errors"
        messages = Array(created[:errors]).map { |e| e.respond_to?(:message) ? e.message.to_s : e.to_s }.join(" ")
        log("draft_user_errors", count: Array(created[:errors]).size)
        raise CodForm::Errors.build("out_of_stock", fields: { "items" => "error_out_of_stock" }) if messages.match?(STOCK_PATTERN)

        raise CodForm::Errors.build("order_failed")
      else
        log("create_failed", code: created[:code].to_s)
        raise CodForm::Errors.build("order_failed")
      end
    end

    def persist!(order, built, contact, address, attribution, upsell, body)
      tracking = hash(session.tracking).merge(hash(params["tracking"]).slice(*TRACKING_KEYS).transform_values { |v| v.to_s[0, 1000] })
      attrs = {
        status: CodForm::Session::STATUS_ORDERED, order_id: order["id"], order_name: order["name"],
        order_total_cents: order["total_cents"], ordered_at: Time.current, order_error: nil,
        contact: contact, address: address, custom_fields: stored_custom_fields,
        phone_normalized: built.contact["phone_digits"].presence, email_normalized: contact["email"].presence,
        ip: @meta["ip"].to_s.presence || session.ip, attribution: attribution, tracking: tracking,
        upsell: upsell ? upsell.slice("offer_id", "expires_at") : {},
        downsell_offer_id: Integer(params["downsell_offer_id"].to_s, exception: false),
        quote_snapshot: built.public_quote.merge(RESPONSE_KEY => body),
        updated_at: Time.current
      }
      attempts = 0
      begin
        attempts += 1
        session.update_columns(attrs)
      rescue StandardError => e
        retry if attempts < 3

        # The order exists in Shopify. Leave the session in 'ordering' (never back to 'open'):
        # the webhook hook stores the order id and a later submit adopts it.
        log("persist_failed", order_id: order["id"], error: e.class.name)
        report(e)
      end
    end

    def after_order(built, order)
      safely("usage") { CodForm::CapService.record_order!(shop, session) }
      safely("funnel") do
        CodForm::FunnelLogger.log(
          shop_id: shop.id, session_token: session.public_id, type: "cf_order_created",
          meta: CodForm::QuoteService.funnel_meta(session).merge(
            "value_cents" => order["total_cents"], "currency" => order["currency"],
            "product_ids" => built.lines.map { |l| l["product_id"] }.uniq.first(20),
            "offer_ids" => self.class.order_offer_ids(built.public_quote)
          ).reject { |_, value| value.respond_to?(:empty?) && value.empty? }
        )
      end
      safely("post_order_job") { CodForm::PostOrderJob.perform_async(session.id) }
      safely("recovery") { mark_recovered_origin }
      safely("setup_state") { mark_test_order } if session.is_test
    end

    # An adopted order is a form order like any other: count it (CAP-1) and run the post-order
    # steps. The compare-and-set in adopt_webhook_order's caller lets this run once per session.
    def after_adopted(order)
      safely("usage") { CodForm::CapService.record_order!(shop, session) }
      safely("funnel") do
        CodForm::FunnelLogger.log(
          shop_id: shop.id, session_token: session.public_id, type: "cf_order_created",
          meta: CodForm::QuoteService.funnel_meta(session).merge("value_cents" => order["total_cents"], "currency" => order["currency"])
        )
      end
      safely("post_order_job") { CodForm::PostOrderJob.perform_async(session.id) }
      safely("setup_state") { mark_test_order } if session.is_test
    end

    # DSH-6: the Setup checklist step "place a test order" is done.
    def mark_test_order
      state = config.setup_state.is_a?(Hash) ? config.setup_state : {}
      return if state["test_order_at"].present?

      config.update_columns(setup_state: state.merge("test_order_at" => Time.current.utc.iso8601), updated_at: Time.current)
    end

    # ABN-2: a recovery session that ordered closes the abandoned session it came from.
    def mark_recovered_origin
      origin = hash(session.tracking)["recovered_from"].to_s
      return if origin.empty?

      CodForm::Session.where(shop_id: shop.id, public_id: origin, status: CodForm::Session::STATUS_ABANDONED)
                      .update_all(status: CodForm::Session::STATUS_RECOVERED, recovered_at: Time.current, updated_at: Time.current)
      shop.abandoned_carts.where(checkout_id: "codf_#{origin}").update_all(notes: "Recovered", updated_at: Time.current)
    end

    # 16. one upsell per order: the highest-priority active upsell that matches the cart.
    def pick_upsell(built)
      offer = built.offers.upsell
      return nil unless offer.is_a?(Hash)

      offer_config = hash(offer["config"])
      variant_id = offer_config["variant_id"].to_s
      # Already added from the pre-purchase upsell popup: not offered a second time.
      return nil if Array(hash(built.public_quote)["extra_lines"]).any? { |line| line.is_a?(Hash) && line["variant_id"].to_s == variant_id }

      quantity = [offer_config["quantity"].to_i, 1].max
      variant = CodForm::CatalogService.variants(shop, [variant_id], country: built.address["country"])[variant_id]
      return nil unless CodForm::UpsellService.purchasable?(variant, quantity)

      price = variant["unit_price_cents"].to_i
      minutes = built.general["upsell_window_minutes"].to_i
      minutes = 5 unless minutes.positive?
      {
        "offer_id" => offer["id"], "config" => offer_config,
        "variant" => {
          "id" => variant_id, "title" => [variant["title"], variant["variant_title"]].reject { |t| t.to_s.empty? }.join(" - "),
          "image" => variant["image"], "price_cents" => price,
          "discounted_price_cents" => CodForm::UpsellService.discounted_unit_price(offer_config, price, quantity)
        },
        "expires_at" => (Time.current + minutes.minutes).utc.iso8601
      }
    rescue StandardError => e
      log("upsell_pick_failed", error: e.class.name)
      nil
    end

    # ---- response (D.6) ------------------------------------------------------------------------

    def build_response(order, built, contact, form_config, upsell, attribution, verified)
      thank_you = CodForm::Engine::ThankYou.resolve(
        config: form_config, locale: session.locale,
        order: order.merge("total_formatted" => CodForm::Engine::Money.format(order["total_cents"], built.money_format)),
        contact: contact
      )
      body = {
        "ok" => true,
        "order" => order.slice("id", "name", "number", "total_cents", "currency", "status_url"),
        "thank_you" => thank_you,
        "upsell" => upsell,
        "events" => self.class.event_ids(order["id"]).merge(
          "value_cents" => order["total_cents"],
          "currency" => order["currency"], "content_ids" => built.lines.map { |l| l["variant_id"] },
          "num_items" => built.lines.sum { |l| l["quantity"].to_i }
        ),
        "web_pixel" => {
          "orderId" => order["id"], "totalPrice" => CodForm::Engine::Money.to_decimal_string(order["total_cents"]),
          "currencyCode" => order["currency"], "email" => contact["email"].to_s, "attribution" => attribution
        },
        "test" => session.is_test ? true : false
      }
      # F.7: order first, OTP afterwards.
      if built.general.dig("otp", "mode").to_s == "order_first" && CodForm::OtpService.on?(setting, built.general) && !verified
        body["otp"] = { "pending" => true }
      end
      body
    end

    # ---- async (ORD-9) -------------------------------------------------------------------------

    def enqueue_async(prepared)
      snapshot = (session.cart_snapshot.is_a?(Hash) ? session.cart_snapshot : {}).merge(
        "items" => prepared[:built].items,
        SUBMIT_KEY => {
          "params" => params.slice("idempotency_key", "items", "contact", "address", "custom_fields", "fields",
                                   "marketing_consent", "shipping_rate_id", "bumps", "pre_upsells", "discount_code", "downsell_offer_id",
                                   "payment_option_id", "expected_total_cents", "tracking", "attribution"),
          "request_meta" => @meta.slice("ip", "user_agent")
        }
      )
      session.update_columns(cart_snapshot: snapshot, updated_at: Time.current)
      CodForm::CreateOrderJob.perform_async(session.id)
    end

    def wait_for_async
      deadline = Time.current + ASYNC_WAIT_SECONDS
      while Time.current < deadline
        sleep ASYNC_POLL_SECONDS
        status, order_id, order_error = CodForm::Session.where(id: session.id).pick(:status, :order_id, :order_error)
        if order_id.present?
          session.reload
          return Result.new(201, self.class.stored_response(session) || self.class.minimal_response(session))
        end
        if status != CodForm::Session::STATUS_ORDERING
          code = CodForm::Errors.known?(order_error.to_s) ? order_error.to_s : "order_failed"
          raise CodForm::Errors.build(code, extra: code == "order_failed" ? { "order_error" => order_error.to_s } : nil)
        end
      end
      Result.new(202, self.class.processing_body)
    end

    # ---- helpers -------------------------------------------------------------------------------

    def published_form_config
      form = session.cod_form_id ? CodForm::Form.find_by(id: session.cod_form_id, shop_id: shop.id) : nil
      form ||= CodForm::Form.default_for(shop)
      form.published_config.is_a?(Hash) ? form.published_config : {}
    end

    # With the single "Full name" field (the form's last_name field is off) the whole name
    # arrives as first_name: the last word becomes the last name, as Shopify expects two parts.
    # A form that asks for both names is never touched.
    # Ids of the offers that are part of an order (analytics: orders and revenue per offer):
    # quantity offers and an accepted downsell appear as discounts, order bumps and free gifts
    # as extra lines.
    def self.order_offer_ids(quote)
      quote = quote.is_a?(Hash) ? quote : {}
      ids = Array(quote["discounts"]) + Array(quote["extra_lines"])
      ids.filter_map { |row| row.is_a?(Hash) ? row["offer_id"] : nil }.map(&:to_s).reject(&:empty?).uniq.first(20)
    end

    def self.split_name(first, last, one_field)
      first = first.to_s.strip
      last = last.to_s.strip
      return [first, last] unless one_field && last.empty?

      head, _space, tail = first.rpartition(/\s+/)
      head.empty? ? [first, ""] : [head, tail]
    end

    def one_name_field?
      fields = Array(published_form_config["fields"])
      fields.none? { |field| field.is_a?(Hash) && field["key"] == "last_name" && field["enabled"] != false }
    end

    def buyer_contact(phone)
      raw = hash(params["contact"])
      first, last = self.class.split_name(CodForm::QuoteService.limit(raw["first_name"]), CodForm::QuoteService.limit(raw["last_name"]), one_name_field?)
      {
        "first_name" => first,
        "last_name" => last,
        "email" => CodForm::QuoteService.limit(raw["email"]).downcase,
        "phone_e164" => phone["valid"] == true ? phone["e164"].to_s : "",
        "phone_national" => phone["valid"] == true ? phone["national"].to_s : ""
      }
    end

    def note_fields
      fields = hash(params["fields"])
      { "gst_number" => fields["gst_number"].to_s.strip[0, 30], "note" => fields["note"].to_s.strip[0, 500] }
    end

    # FRM-13: custom field values become visible order "additional details", labelled with the
    # merchant's own label text.
    def custom_field_rows(form_config)
      values = hash(params["custom_fields"])
      texts = hash(form_config["texts"])
      locale_texts = hash(texts[session.locale.to_s]).merge(hash(texts[session.locale.to_s.split(/[-_]/).first.to_s])) { |_, a, _| a }
      Array(form_config["fields"]).filter_map do |field|
        next unless field.is_a?(Hash) && field["enabled"] == true && field["key"].to_s.match?(/\Acf_[a-z0-9]{8}\z/)

        value = values[field["key"]]
        value = value.join(", ") if value.is_a?(Array)
        value = value == true ? "Yes" : value.to_s.strip[0, 500]
        next if value.empty? || value == "false"

        label = locale_texts["label_#{field['key']}"].presence || hash(texts["en"])["label_#{field['key']}"].presence || field["key"]
        { "label" => label.to_s[0, 80], "value" => value }
      end
    end

    def stored_custom_fields
      stored = hash(params["custom_fields"]).first(30).to_h.transform_values { |v| v.is_a?(Array) ? v.map(&:to_s).first(20) : v.to_s[0, 500] }
                                            .merge("marketing_consent" => params["marketing_consent"] == true)
      # The order note and GST number (D.6 `fields`) are kept next to the custom fields so the
      # Google Sheets row (`note` column, I.5) and exports can show them. Buyer text: it lives
      # only in this column (blanked by SessionPurgeJob / PrivacyService) and is never logged.
      note_fields.each { |key, value| stored[key] = value unless value.empty? }
      stored
    end

    def hash(value)
      value.is_a?(Hash) ? value : {}
    end

    def numeric(value)
      value.is_a?(Numeric) ? value : nil
    end

    def safely(step)
      yield
    rescue StandardError => e
      log("after_order_step_failed", step: step, error: e.class.name)
    end

    # Ids and codes only — never contact data.
    def log(event, **fields)
      details = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
      Rails.logger.info("[CodForm::OrderService] #{event} shop_id=#{shop.id} session=#{session.public_id} #{details}")
    end

    def report(error)
      Sentry.capture_exception(error) if defined?(Sentry)
    rescue StandardError
      nil
    end
  end
end
