# frozen_string_literal: true

module CodForm
  # CodForm::PostOrderJob.perform_async(session_id)   (K.9, ARCHITECTURE.md I.3)
  # CodForm::PostOrderJob.perform_async(session_id, "handoff")   (partial order paid at checkout)
  #
  # Everything that happens after a form order exists and must never fail the order:
  #   1. server pixels (Purchase / Lead) with the shared event id
  #   2. marketing consent on the Shopify customer (FRM-17)
  #   3. Google Sheets row (INT-1)
  #   4. Klaviyo / Omnisend "COD Form Order Placed" (INT-2)
  #   5. overage count for paid shops beyond their cap (CAP-9; inert without a rate)
  #   6. recovery bookkeeping: abandoned sessions this order recovers (ABN-2)
  #
  # Each step is independent and rescued. Steps that need retries have their own jobs; steps
  # that must not run twice carry their own once-only guard, so a re-run of this job is safe.
  class PostOrderJob < ApplicationJob
    sidekiq_options queue: "default", retry: 2

    STEPS = %i[pixels marketing_consent google_sheets crm overage recovery].freeze
    # A partial order that started in the form and was paid at Shopify checkout (F.5 c, PRE-10,
    # CAP-1) is a counted form order: it gets its Sheets row, its CRM event and the overage
    # count. It gets no server pixel and no consent update from here: the order was placed in
    # Shopify checkout, whose own pixels and consent box already reported it.
    HANDOFF_STEPS = %i[google_sheets crm overage recovery].freeze
    ORIGIN_HANDOFF = "handoff"
    GUARD_TTL = 7.days

    # origin: nil for an order created by the form (CodForm::OrderService), "handoff" when
    # CodForm::OrderWebhookHook#finish_handoff enqueues it for a partial order.
    def perform(session_id, origin = nil)
      session = CodForm::Tracking::ServerDispatchJob.find_session(session_id)
      return if session.nil? || session.order_id.blank?

      shop = session.shop
      return if shop.nil?

      (origin.to_s == ORIGIN_HANDOFF ? HANDOFF_STEPS : STEPS).each do |step|
        send(step, shop, session)
      rescue StandardError => e
        Rails.logger.warn("[codf/post_order] shop=#{shop.id} session=#{session.id} step=#{step} failed: #{e.class}")
      end
    end

    private

    # Test orders (codking_form_test) stay out of ad platforms, sheets, CRMs and billing.
    def pixels(_shop, session)
      return if session.is_test

      CodForm::Tracking::ServerDispatchJob.perform_async(session.id, CodForm::Tracking::EventMap::MOMENT_PURCHASE)
    end

    def marketing_consent(shop, session)
      return if session.is_test
      return unless CodForm::Integrations::MarketingConsent.given?(session)
      return unless once("consent", session)

      CodForm::Integrations::MarketingConsent.call(shop, session, channels: consent_channels(session))
    end

    def google_sheets(shop, session)
      return if session.is_test
      return if CodForm::Integrations::Registry.active(shop, "google_sheets").nil?

      CodForm::Integrations::GoogleSheetsAppendJob.perform_async(session.id)
    end

    def crm(shop, session)
      return if session.is_test

      payloads = CodForm::Integrations::EventPayloads
      data = session.attributes.slice("order_id", "order_name", "order_total_cents", "currency", "country_code",
                                      "contact", "address", "quote_snapshot", "attribution")
      profile = payloads.profile_from_session(data)
      properties = payloads.order_properties(data)
      unique = "order_#{session.order_id}"
      time = session.ordered_at || Time.current

      if CodForm::Integrations::Registry.active(shop, "klaviyo") && once("klaviyo", session)
        CodForm::Integrations::KlaviyoClient.track(
          shop, event: payloads::EVENT_ORDER, profile: profile, properties: properties, time: time,
                value_cents: session.order_total_cents, currency: session.currency, unique_id: unique
        )
      end
      if CodForm::Integrations::Registry.active(shop, "omnisend") && once("omnisend", session)
        CodForm::Integrations::OmnisendClient.track(
          shop, event: payloads::EVENT_ORDER, profile: profile, properties: properties, time: time, event_id: unique
        )
      end
    end

    def overage(shop, session)
      return if session.is_test
      return unless once("overage", session)

      CodForm::OverageBillingJob.record_over_cap!(shop)
    end

    def recovery(shop, session)
      CodForm::Abandonment::RecoveryService.complete!(shop, session)
    end

    # True the first time it is asked for (step, order). Redis-backed CodForm::Cache.store.
    def once(step, session)
      CodForm::Cache.store.write("codf:po:#{step}:#{session.order_id}", 1, unless_exist: true, expires_in: GUARD_TTL) ? true : false
    end

    # Channels of the form's marketing_consent field; both when the field does not say.
    def consent_channels(session)
      config = session.form&.published_config
      fields = config.is_a?(Hash) ? Array(config["fields"]) : []
      field = fields.find { |f| f.is_a?(Hash) && f["key"] == "marketing_consent" }
      channels = field ? Array(field["channels"]).map(&:to_s) : []
      channels.empty? ? CodForm::Integrations::MarketingConsent::CHANNELS : channels
    rescue StandardError
      CodForm::Integrations::MarketingConsent::CHANNELS
    end
  end
end
