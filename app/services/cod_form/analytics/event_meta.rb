# frozen_string_literal: true

require "time"

module CodForm
  module Analytics
    # Pure helpers for funnel-event metadata (ARCHITECTURE.md I.1). No Rails.
    module EventMeta
      PREFIX = "cf_"

      # The full cf_* taxonomy.
      EVENT_TYPES = %w[
        cf_button_view cf_form_open cf_first_input cf_shipping_selected cf_submit_attempt cf_submit_error
        cf_order_created cf_form_close cf_prepaid_redirect cf_partial_handoff cf_prepaid_order
        cf_otp_sent cf_otp_verified cf_otp_bypassed cf_offer_view cf_offer_accept cf_downsell_shown cf_downsell_accept
        cf_upsell_view cf_upsell_accept cf_recovery_open cf_blocked cf_fallback cf_client_error
      ].freeze

      # Accepted from the browser through POST /api/form/events. Everything else is
      # server-authoritative and dropped when a browser sends it.
      BROWSER_EVENT_TYPES = %w[
        cf_button_view cf_first_input cf_shipping_selected cf_submit_attempt cf_submit_error cf_form_close
        cf_offer_view cf_offer_accept cf_downsell_shown cf_downsell_accept cf_upsell_view cf_fallback
        cf_client_error
      ].freeze

      SERVER_EVENT_TYPES = (EVENT_TYPES - BROWSER_EVENT_TYPES).freeze

      BUTTON_VIEW = "cf_button_view"
      CLIENT_ERROR = "cf_client_error"

      MAX_EVENTS_PER_CALL = 20
      MAX_META_KEYS = 20
      MAX_STRING = 200
      MAX_ARRAY = 20
      DEVICES = %w[mobile tablet desktop].freeze

      # Keys a browser may set. PII never belongs in event metadata, so free-form keys are
      # not accepted: anything outside this list is dropped.
      CLIENT_META_KEYS = %w[
        page product_id product_ids country device source form_id field step reason code offer_id offer_type
        variant_id quantity shipping_rate_id value_cents currency utm_campaign ab tier_index message
      ].freeze

      module_function

      def known?(type)
        EVENT_TYPES.include?(type.to_s)
      end

      def browser_allowed?(type)
        BROWSER_EVENT_TYPES.include?(type.to_s)
      end

      # Metadata every event of a session carries (I.1): country, device, source, form_id,
      # plus product_ids, utm_campaign, ab and test when known.
      # session: plain Hash with string keys (CodForm::Session attributes).
      def base_from_session(session)
        return {} unless session.is_a?(Hash)

        quote = session["quote_snapshot"].is_a?(Hash) ? session["quote_snapshot"] : {}
        lines = quote["lines"].is_a?(Array) ? quote["lines"] : []
        product_ids = lines.filter_map { |l| l.is_a?(Hash) ? text(l["product_id"]) : nil }.uniq.first(MAX_ARRAY)
        attribution = session["attribution"].is_a?(Hash) ? session["attribution"] : {}
        ab = session["ab_assignments"].is_a?(Hash) ? session["ab_assignments"] : {}

        meta = {
          "country" => country(session["country_code"]),
          "device" => device(session["device"]),
          "source" => text(session["source"]),
          "form_id" => session["cod_form_id"].nil? ? nil : session["cod_form_id"].to_s
        }
        meta["product_ids"] = product_ids unless product_ids.empty?
        campaign = text(attribution["utm_campaign"])
        meta["utm_campaign"] = campaign if campaign
        meta["ab"] = ab.to_h { |k, v| [k.to_s, v.to_s[0, 40]] } unless ab.empty?
        meta["test"] = true if session["is_test"] == true
        meta.reject { |_, v| v.nil? }
      end

      # Cleans metadata sent by a browser: whitelisted keys, scalar values, bounded sizes.
      def sanitize_client(raw)
        return {} unless raw.is_a?(Hash)

        out = {}
        raw.each do |key, value|
          key = key.to_s
          next unless CLIENT_META_KEYS.include?(key)

          clean = clean_value(key, value)
          out[key] = clean unless clean.nil?
          break if out.size >= MAX_META_KEYS
        end
        out["country"] = country(out["country"]) if out.key?("country")
        out["device"] = device(out["device"]) if out.key?("device")
        if out.key?("product_id") && !out.key?("product_ids")
          out["product_ids"] = [out["product_id"].to_s]
        end
        out.reject { |_, v| v.nil? }
      end

      # Session facts win over what the browser claims; the result has at most 20 keys.
      def merge(base, client)
        base = base.is_a?(Hash) ? base : {}
        merged = base.merge(sanitize_client(client).reject { |key, _| base.key?(key) })
        merged.first(MAX_META_KEYS).to_h
      end

      # "<country>|<device>|<product_id>" — the Redis hash field of a button view (I.1).
      def button_view_field(meta)
        meta = meta.is_a?(Hash) ? meta : {}
        product = text(meta["product_id"]) || Array(meta["product_ids"]).first.to_s
        product = "" unless product.to_s.match?(/\A[0-9A-Za-z_-]{1,32}\z/)
        [country(meta["country"]).to_s, device(meta["device"]).to_s, product.to_s].join("|")
      end

      def parse_button_view_field(field)
        country, device, product = field.to_s.split("|", 3)
        { "country" => country.to_s, "device" => device.to_s, "product_id" => product.to_s }
      end

      # Browser timestamps are trusted only inside [now - max_age, now + 5 min].
      def clamp_time(raw, now:, max_age: 86_400)
        parsed = raw.is_a?(Time) ? raw : Time.iso8601(raw.to_s)
        return now if parsed > now + 300 || parsed < now - max_age

        parsed
      rescue ArgumentError, TypeError
        now
      end

      def country(value)
        code = value.to_s.strip.upcase
        code.match?(/\A[A-Z]{2}\z/) ? code : nil
      end

      def device(value)
        name = value.to_s.strip.downcase
        DEVICES.include?(name) ? name : nil
      end

      def text(value)
        return nil if value.nil? || value.is_a?(Hash) || value.is_a?(Array)

        out = value.to_s.strip
        out.empty? ? nil : out[0, MAX_STRING]
      end

      def clean_value(key, value)
        case value
        when String then text(value)
        when Integer then value
        when Float then value.finite? ? value : nil
        when true, false then value
        when Array
          return nil unless key == "product_ids"

          list = value.filter_map { |v| text(v) }.first(MAX_ARRAY)
          list.empty? ? nil : list
        when Hash
          return nil unless key == "ab"

          value.first(10).to_h { |k, v| [k.to_s[0, 40], v.to_s[0, 40]] }
        end
      end
    end
  end
end
