# frozen_string_literal: true

module CodForm
  # CodForm::EventIngestService.call(shop:, session:, client_id:, events:, request_meta:)   (K.9)
  #
  # Handles POST /api/form/events (ARCHITECTURE.md D.10, I.1). The controller always answers
  # 204, so this never raises. Returns {accepted:, dropped:}.
  #
  #   - at most 20 events per call; the rest are dropped
  #   - unknown types and server-authoritative types are dropped
  #   - cf_button_view -> Redis counter; cf_client_error -> Sentry; others -> form_funnel_events
  #   - session_token = session public_id, or client_id for pre-session events
  #   - with general.consent.respect_customer_privacy, a session without analytics consent
  #     writes no browser funnel events (G.8)
  class EventIngestService
    def self.call(shop:, session: nil, client_id: nil, events: nil, request_meta: nil)
      new(shop, session, client_id, events, request_meta).call
    rescue StandardError => e
      Rails.logger.warn("[codf/events] ingest failed shop=#{shop&.id} #{e.class}")
      { accepted: 0, dropped: Array(events).size }
    end

    def initialize(shop, session, client_id, events, request_meta)
      @shop = shop
      @session = session
      @client_id = client_id.to_s.strip[0, 64]
      @events = events.is_a?(Array) ? events : []
      @request_meta = request_meta.respond_to?(:to_h) ? request_meta.to_h.stringify_keys : {}
    end

    def call
      return { accepted: 0, dropped: @events.size } if @shop.nil?

      meta_helper = CodForm::Analytics::EventMeta
      taken = @events.first(meta_helper::MAX_EVENTS_PER_CALL)
      dropped = @events.size - taken.size
      now = Time.current
      rows = []
      accepted = 0

      taken.each do |event|
        event = event.respond_to?(:to_unsafe_h) ? event.to_unsafe_h : event
        unless event.is_a?(Hash)
          dropped += 1
          next
        end
        event = event.stringify_keys
        type = event["type"].to_s
        unless meta_helper.browser_allowed?(type)
          dropped += 1
          next
        end

        raw_meta = event["meta"].respond_to?(:to_unsafe_h) ? event["meta"].to_unsafe_h : event["meta"]
        raw_meta = raw_meta.is_a?(Hash) ? raw_meta.deep_stringify_keys : {}
        meta = meta_helper.merge(base_meta, raw_meta)
        at = meta_helper.clamp_time(event["at"], now: now)

        case type
        when meta_helper::BUTTON_VIEW
          next (dropped += 1) if test_session? || !analytics_allowed?

          CodForm::FunnelLogger.count_button_view(@shop.id, meta, at)
          accepted += 1
        when meta_helper::CLIENT_ERROR
          CodForm::FunnelLogger.log(shop_id: @shop.id, session_token: token, type: type, meta: meta, at: at)
          accepted += 1
        else
          if token.empty? || !analytics_allowed?
            dropped += 1
            next
          end
          rows << { type: type, session_token: token, meta: meta, at: at }
        end
      end

      accepted += CodForm::FunnelLogger.log_many(shop_id: @shop.id, rows: rows)
      bump_closes(rows)
      { accepted: accepted, dropped: dropped }
    end

    private

    def token
      @token ||= (@session&.public_id.presence || @client_id).to_s
    end

    def test_session?
      @session&.is_test ? true : false
    end

    def base_meta
      @base_meta ||= begin
        base = @session ? CodForm::Analytics::EventMeta.base_from_session(@session.attributes) : {}
        country = @request_meta["country"].to_s
        base["country"] ||= CodForm::Analytics::EventMeta.country(country) if base["country"].nil? && country.present?
        base.compact
      end
    end

    # G.8: funnel analytics need analytics consent when the shop respects the privacy API.
    def analytics_allowed?
      return @analytics_allowed if defined?(@analytics_allowed)

      @analytics_allowed =
        if @session.nil?
          true
        else
          tracking = @session.tracking.is_a?(Hash) ? @session.tracking : {}
          consent = tracking["consent"].is_a?(Hash) ? tracking["consent"] : {}
          consent["analytics"] != false || !respect_privacy?
        end
    end

    def respect_privacy?
      general = CodForm::ShopConfig.for(@shop).general
      consent = general.is_a?(Hash) && general["consent"].is_a?(Hash) ? general["consent"] : {}
      consent["respect_customer_privacy"] != false
    end

    # closes_count drives the "downsell on first close" rule (B.8).
    def bump_closes(rows)
      return if @session.nil?

      closes = rows.count { |row| row[:type] == "cf_form_close" }
      return if closes.zero?

      CodForm::Session.where(id: @session.id).update_all(["closes_count = closes_count + ?", closes])
    end
  end
end
