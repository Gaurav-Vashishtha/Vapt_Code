# frozen_string_literal: true

require "digest"
# Plain Ruby (tests) loads the sibling itself; under Rails Zeitwerk autoloads it.
require_relative "event_map" unless defined?(::Rails)

module CodForm
  module Tracking
    # Pure payload builders for the server-side pixel APIs (ARCHITECTURE.md I.3).
    # In: a pixel hash (C.6, string keys) and an event hash (EventBuilder.build).
    # Out: the JSON body (a Hash with string keys) for the vendor endpoint, or nil when this
    # pixel gets nothing for this moment. No I/O, no Rails, nothing is logged.
    #
    # PII is normalised and SHA-256 hashed where the vendor requires it:
    #   Meta, Snapchat, Pinterest: email lower-case trimmed; phone digits with country code.
    #   TikTok: email lower-case trimmed; phone in E.164 including "+".
    #   GA4 Measurement Protocol: no PII is sent at all.
    module Payloads
      module_function

      # ---- Meta Conversions API: POST /v19.0/<pixel_id>/events ----------------------------
      def meta(pixel:, event:)
        name, id = name_and_id("meta", pixel, event)
        return nil if name.nil? || id.nil?

        user = event["user"] || {}
        user_data = compact(
          "em" => hashed_list(norm_email(user["email"])),
          "ph" => hashed_list(norm_phone_digits(user["phone_e164"])),
          "fn" => hashed_list(norm_name(user["first_name"])),
          "ln" => hashed_list(norm_name(user["last_name"])),
          "ct" => hashed_list(norm_city(user["city"])),
          "zp" => hashed_list(norm_zip(user["zip"])),
          "country" => hashed_list(norm_country(user["country"])),
          "external_id" => hashed_list(present(user["external_id"])),
          "fbp" => present(user["fbp"]),
          "fbc" => present(user["fbc"]),
          "client_ip_address" => present(user["ip"]),
          "client_user_agent" => present(user["user_agent"])
        )
        custom_data = compact(
          "value" => amount(event["value_cents"]),
          "currency" => present(event["currency"]),
          "content_type" => event["contents"].to_a.empty? ? nil : "product",
          "content_ids" => content_ids(event),
          "contents" => event["contents"].to_a.map do |c|
            { "id" => c["id"], "quantity" => c["quantity"], "item_price" => amount(c["price_cents"]) }
          end,
          "num_items" => positive(event["num_items"]),
          "order_id" => present(event["order_id"])
        )
        body = {
          "data" => [compact(
            "event_name" => name,
            "event_time" => event["event_time"].to_i,
            "event_id" => id,
            "action_source" => "website",
            "event_source_url" => present(event["page_url"]),
            "user_data" => user_data,
            "custom_data" => custom_data
          )]
        }
        test_code = present(config_of(pixel)["test_event_code"])
        body["test_event_code"] = test_code if test_code
        body
      end

      # ---- TikTok Events API: POST /open_api/v1.3/event/track/ -----------------------------
      def tiktok(pixel:, event:)
        name, id = name_and_id("tiktok", pixel, event)
        return nil if name.nil? || id.nil?

        user = event["user"] || {}
        body = {
          "event_source" => "web",
          "event_source_id" => pixel["pixel_id"].to_s,
          "data" => [compact(
            "event" => name,
            "event_time" => event["event_time"].to_i,
            "event_id" => id,
            "user" => compact(
              "email" => sha256(norm_email(user["email"])),
              "phone" => sha256(norm_phone_e164(user["phone_e164"])),
              "external_id" => sha256(present(user["external_id"])),
              "ttp" => present(user["ttp"]),
              "ttclid" => present(user["ttclid"]),
              "ip" => present(user["ip"]),
              "user_agent" => present(user["user_agent"])
            ),
            "properties" => compact(
              "value" => amount(event["value_cents"]),
              "currency" => present(event["currency"]),
              "content_type" => "product",
              "contents" => event["contents"].to_a.map do |c|
                compact("content_id" => c["id"], "content_name" => c["title"],
                        "quantity" => c["quantity"], "price" => amount(c["price_cents"]))
              end,
              "order_id" => present(event["order_id"])
            ),
            "page" => compact("url" => present(event["page_url"]))
          )]
        }
        test_code = present(config_of(pixel)["test_event_code"])
        body["test_event_code"] = test_code if test_code
        body
      end

      # ---- GA4 Measurement Protocol: POST /mp/collect ---------------------------------------
      # Deduplication against the browser's gtag purchase is by transaction_id.
      def ga4(pixel:, event:)
        name, _id = name_and_id("ga4", pixel, event)
        return nil if name.nil?

        user = event["user"] || {}
        client_id = present(user["ga_client_id"]) || present(user["external_id"]) || present(event["session_id"])
        return nil if client_id.nil?

        items = event["contents"].to_a.map do |c|
          compact("item_id" => c["id"], "item_name" => c["title"],
                  "price" => amount(c["price_cents"]), "quantity" => c["quantity"])
        end
        params = compact(
          "currency" => present(event["currency"]),
          "value" => amount(event["value_cents"]),
          "items" => items,
          "engagement_time_msec" => 1,
          "session_id" => present(user["ga_session_id"])
        )
        if name == "purchase"
          params["transaction_id"] = event["order_id"].to_s
          params["shipping"] = amount(event["shipping_cents"]) if event["shipping_cents"].to_i.positive?
          params["tax"] = amount(event["tax_cents"]) if event["tax_cents"].to_i.positive?
          params["coupon"] = event["coupon"] if present(event["coupon"])
        end
        params["debug_mode"] = 1 if present(config_of(pixel)["test_event_code"])

        marketing = (event["consent"] || {})["marketing"] != false
        granted = marketing ? "GRANTED" : "DENIED"
        {
          "client_id" => client_id,
          "timestamp_micros" => event["event_time"].to_i * 1_000_000,
          "non_personalized_ads" => !marketing,
          "consent" => { "ad_user_data" => granted, "ad_personalization" => granted },
          "events" => [{ "name" => name, "params" => params }]
        }
      end

      # ---- Snapchat Conversions API v3: POST /v3/<pixel_id>/events --------------------------
      def snapchat(pixel:, event:)
        name, id = name_and_id("snapchat", pixel, event)
        return nil if name.nil? || id.nil?

        user = event["user"] || {}
        {
          "data" => [compact(
            "event_name" => name,
            "event_time" => event["event_time"].to_i,
            "event_id" => id,
            "action_source" => "WEB",
            "event_source_url" => present(event["page_url"]),
            "user_data" => compact(
              "em" => hashed_list(norm_email(user["email"])),
              "ph" => hashed_list(norm_phone_digits(user["phone_e164"])),
              "fn" => hashed_list(norm_name(user["first_name"])),
              "ln" => hashed_list(norm_name(user["last_name"])),
              "ct" => hashed_list(norm_city(user["city"])),
              "zp" => hashed_list(norm_zip(user["zip"])),
              "country" => hashed_list(norm_country(user["country"])),
              "external_id" => hashed_list(present(user["external_id"])),
              "client_ip_address" => present(user["ip"]),
              "client_user_agent" => present(user["user_agent"]),
              "sc_click_id" => present(user["sccid"]),
              "sc_cookie1" => present(user["sc_cookie1"])
            ),
            "custom_data" => compact(
              "value" => amount(event["value_cents"]),
              "currency" => present(event["currency"]),
              "content_ids" => content_ids(event),
              "contents" => event["contents"].to_a.map do |c|
                { "id" => c["id"], "quantity" => c["quantity"], "item_price" => amount(c["price_cents"]) }
              end,
              "num_items" => positive(event["num_items"]),
              "order_id" => present(event["order_id"])
            )
          )]
        }
      end

      # ---- Pinterest Conversions API: POST /v5/ad_accounts/<id>/events ----------------------
      # Amounts are strings in this API.
      def pinterest(pixel:, event:)
        name, id = name_and_id("pinterest", pixel, event)
        return nil if name.nil? || id.nil?

        user = event["user"] || {}
        {
          "data" => [compact(
            "event_name" => name,
            "action_source" => "web",
            "event_time" => event["event_time"].to_i,
            "event_id" => id,
            "event_source_url" => present(event["page_url"]),
            "user_data" => compact(
              "em" => hashed_list(norm_email(user["email"])),
              "ph" => hashed_list(norm_phone_digits(user["phone_e164"])),
              "fn" => hashed_list(norm_name(user["first_name"])),
              "ln" => hashed_list(norm_name(user["last_name"])),
              "ct" => hashed_list(norm_city(user["city"])),
              "zp" => hashed_list(norm_zip(user["zip"])),
              "country" => hashed_list(norm_country(user["country"])),
              "external_id" => hashed_list(present(user["external_id"])),
              "client_ip_address" => present(user["ip"]),
              "client_user_agent" => present(user["user_agent"]),
              "click_id" => present(user["epik"])
            ),
            "custom_data" => compact(
              "currency" => present(event["currency"]),
              "value" => amount_string(event["value_cents"]),
              "content_ids" => content_ids(event),
              "contents" => event["contents"].to_a.map do |c|
                { "id" => c["id"], "item_price" => amount_string(c["price_cents"]), "quantity" => c["quantity"] }
              end,
              "num_items" => positive(event["num_items"]),
              "order_id" => present(event["order_id"])
            )
          )]
        }
      end

      # Platform => builder. google_ads has no payload here (see GoogleAdsClient).
      def build(pixel:, event:)
        case pixel["platform"].to_s
        when "meta" then meta(pixel: pixel, event: event)
        when "tiktok" then tiktok(pixel: pixel, event: event)
        when "ga4" then ga4(pixel: pixel, event: event)
        when "snapchat" then snapchat(pixel: pixel, event: event)
        when "pinterest" then pinterest(pixel: pixel, event: event)
        end
      end

      # ---- helpers --------------------------------------------------------------------------

      def name_and_id(platform, pixel, event)
        config = config_of(pixel)
        moment = event["moment"]
        return [nil, nil] unless EventMap.moment_enabled?(config, moment)

        name = EventMap.event_name(platform: platform, moment: moment, config: config)
        id = EventMap.event_id(moment: moment, session_id: event["session_id"], order_id: event["order_id"],
                               purchase_event: config["purchase_event"])
        [name, id]
      end

      def config_of(pixel)
        pixel["config"].is_a?(Hash) ? pixel["config"] : {}
      end

      def content_ids(event)
        event["contents"].to_a.map { |c| c["id"] }
      end

      # Integer cents (amount x 100, every currency) -> decimal number for the vendor.
      def amount(cents)
        return nil if cents.nil?

        (cents.to_i / 100.0).round(2)
      end

      def amount_string(cents)
        return nil if cents.nil?

        format("%.2f", cents.to_i / 100.0)
      end

      def positive(number)
        number.to_i.positive? ? number.to_i : nil
      end

      def present(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def sha256(value)
        value.nil? ? nil : Digest::SHA256.hexdigest(value)
      end

      def hashed_list(value)
        value.nil? ? nil : [Digest::SHA256.hexdigest(value)]
      end

      def norm_email(value)
        text = present(value)
        return nil if text.nil? || !text.include?("@")

        text.downcase
      end

      # Digits only, with country code, no "+" and no leading zeros (Meta / Snapchat / Pinterest).
      def norm_phone_digits(value)
        digits = value.to_s.gsub(/\D/, "").sub(/\A0+/, "")
        digits.length.between?(8, 15) ? digits : nil
      end

      # E.164 with "+" (TikTok).
      def norm_phone_e164(value)
        digits = norm_phone_digits(value)
        digits.nil? ? nil : "+#{digits}"
      end

      def norm_name(value)
        text = present(value)
        text.nil? ? nil : text.downcase
      end

      def norm_city(value)
        text = present(value)
        text.nil? ? nil : text.downcase.gsub(/\s+/, "")
      end

      def norm_zip(value)
        text = present(value)
        text.nil? ? nil : text.downcase.gsub(/[\s-]+/, "")
      end

      def norm_country(value)
        text = present(value)
        text.nil? || text.length != 2 ? nil : text.downcase
      end

      # Drops nil values and empty hashes / arrays.
      def compact(hash)
        hash.reject { |_, v| v.nil? || ((v.is_a?(Hash) || v.is_a?(Array)) && v.empty?) }
      end
    end
  end
end
