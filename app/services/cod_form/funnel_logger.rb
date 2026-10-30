# frozen_string_literal: true

module CodForm
  # CodForm::FunnelLogger.log(shop_id:, session_token:, type:, meta: {}, at: Time.current)   (K.9)
  #
  # Writes one cf_* funnel event (ARCHITECTURE.md I.1). Used by the server for the
  # authoritative events and by EventIngestService for browser events.
  # Never raises: analytics must not break a buyer request. Returns true when recorded.
  #
  # cf_button_view is not stored as a row: it is a Redis counter
  #   HINCRBY codf:bv:<shop_id>:<yyyy-mm-dd> "<country>|<device>|<product_id>" 1   (TTL 3 days)
  # with the date in the shop's time zone; the rollup job folds it into cod_form_daily_stats.
  # cf_client_error goes to Sentry and is not stored.
  class FunnelLogger
    BUTTON_VIEW_TTL = 3.days.to_i
    BUTTON_VIEW_MAX_FIELDS = 5_000

    class << self
      def log(shop_id:, session_token:, type:, meta: {}, at: Time.current)
        type = type.to_s
        return false unless CodForm::Analytics::EventMeta.known?(type)

        meta = normalize_meta(meta)
        case type
        when CodForm::Analytics::EventMeta::BUTTON_VIEW
          count_button_view(shop_id, meta, at)
        when CodForm::Analytics::EventMeta::CLIENT_ERROR
          report_client_error(shop_id, meta)
        else
          return false if session_token.to_s.empty?

          meta = enrich(shop_id, session_token, meta)
          FormFunnelEvent.create!(
            shop_id: shop_id, session_token: session_token.to_s, event_type: type,
            occurred_at: at || Time.current, metadata: meta
          )
          mark_active(shop_id)
        end
        true
      rescue StandardError => e
        Rails.logger.warn("[codf/funnel] log failed shop=#{shop_id} type=#{type} #{e.class}")
        false
      end

      # Bulk form used by the ingest endpoint: rows = [{type:, session_token:, meta:, at:}].
      def log_many(shop_id:, rows:)
        now = Time.current
        records = rows.filter_map do |row|
          next if row[:session_token].to_s.empty?

          {
            shop_id: shop_id, session_token: row[:session_token].to_s, event_type: row[:type].to_s,
            occurred_at: row[:at] || now, metadata: normalize_meta(row[:meta]), created_at: now, updated_at: now
          }
        end
        return 0 if records.empty?

        FormFunnelEvent.insert_all(records)
        mark_active(shop_id)
        records.size
      rescue StandardError => e
        Rails.logger.warn("[codf/funnel] bulk log failed shop=#{shop_id} #{e.class}")
        0
      end

      def button_view_key(shop_id, date)
        "codf:bv:#{shop_id}:#{date.strftime('%Y-%m-%d')}"
      end

      # Set of shop ids with any funnel activity on a UTC date. The rollup job reads it, so it
      # never has to scan form_funnel_events (no index on occurred_at alone) or the key space.
      def active_shops_key(date)
        "codf:active:#{date.strftime('%Y-%m-%d')}"
      end

      def mark_active(shop_id)
        key = active_shops_key(Time.current.utc.to_date)
        Sidekiq.redis do |redis|
          redis.sadd(key, shop_id.to_s)
          redis.expire(key, BUTTON_VIEW_TTL)
        end
      rescue StandardError
        nil
      end

      # {"<country>|<device>|<product_id>" => Integer} for one shop-local day.
      def button_views(shop_id, date)
        raw = Sidekiq.redis { |redis| redis.hgetall(button_view_key(shop_id, date)) } || {}
        raw.transform_values(&:to_i)
      rescue StandardError => e
        Rails.logger.warn("[codf/funnel] button view read failed shop=#{shop_id} #{e.class}")
        {}
      end

      def count_button_view(shop_id, meta, at = Time.current)
        field = CodForm::Analytics::EventMeta.button_view_field(meta)
        zone = CodForm::Analytics::ShopTime.zone_for_id(shop_id)
        key = button_view_key(shop_id, (at || Time.current).in_time_zone(zone).to_date)
        shops_key = active_shops_key(Time.current.utc.to_date)
        Sidekiq.redis do |redis|
          # A hostile client could invent product ids; past the bound everything lands in one field.
          # (HEXISTS answers 1/0 or true/false depending on the Redis client.)
          if redis.hlen(key).to_i >= BUTTON_VIEW_MAX_FIELDS && ![true, 1].include?(redis.hexists(key, field))
            field = "||"
          end
          redis.hincrby(key, field, 1)
          redis.expire(key, BUTTON_VIEW_TTL)
          redis.sadd(shops_key, shop_id.to_s)
          redis.expire(shops_key, BUTTON_VIEW_TTL)
        end
        true
      end

      private

      # I.1: every event carries country, device, source and form_id, plus product_ids,
      # utm_campaign and ab where known. Server callers pass only what they have at hand, so
      # the rest is filled from the session row (one lookup on the unique public_id index).
      # What the caller passed always wins.
      ENRICH_KEYS = %w[country device source form_id product_ids utm_campaign ab].freeze

      def enrich(shop_id, session_token, meta)
        return meta if ENRICH_KEYS.all? { |key| meta.key?(key) }
        return meta unless session_token.to_s.match?(/\A[0-9a-fA-F-]{36}\z/)

        session = CodForm::Session.find_by(shop_id: shop_id, public_id: session_token.to_s)
        return meta if session.nil?

        base = CodForm::Analytics::EventMeta.base_from_session(session.attributes)
        base.merge(meta).first(CodForm::Analytics::EventMeta::MAX_META_KEYS).to_h
      end

      def normalize_meta(meta)
        hash = meta.respond_to?(:to_unsafe_h) ? meta.to_unsafe_h : meta
        hash = hash.is_a?(Hash) ? hash.deep_stringify_keys : {}
        hash.first(CodForm::Analytics::EventMeta::MAX_META_KEYS).to_h
      end

      def report_client_error(shop_id, meta)
        return unless defined?(Sentry)

        Sentry.capture_message(
          "COD Form client error",
          level: :warning,
          extra: {
            shop_id: shop_id,
            code: meta["code"].to_s[0, 80], step: meta["step"].to_s[0, 40],
            message: meta["message"].to_s[0, 200], device: meta["device"], country: meta["country"]
          }
        )
      end
    end
  end
end
