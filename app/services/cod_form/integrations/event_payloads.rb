# frozen_string_literal: true

require "time"

module CodForm
  module Integrations
    # Pure builders for the Klaviyo and Omnisend event bodies (ARCHITECTURE.md I.4, INT-2, ABN-4).
    # Plain hashes in and out; no Rails, no I/O. These vendors take contact data unhashed
    # (that is the purpose of the integration); nothing built here is ever logged.
    module EventPayloads
      EVENT_ORDER = "COD Form Order Placed"
      EVENT_ABANDONED = "COD Form Abandoned"
      EVENTS = [EVENT_ORDER, EVENT_ABANDONED].freeze

      module_function

      # profile: {"email","phone_e164","first_name","last_name","city","province","zip","country"}
      # Returns nil when there is no email and no phone (Klaviyo needs one identifier).
      def klaviyo(event:, profile:, properties:, time: nil, value_cents: nil, currency: nil, unique_id: nil)
        attributes = klaviyo_profile(profile)
        return nil if attributes.nil?

        event_attributes = {
          "properties" => properties.is_a?(Hash) ? properties : {},
          "metric" => { "data" => { "type" => "metric", "attributes" => { "name" => event.to_s } } },
          "profile" => { "data" => { "type" => "profile", "attributes" => attributes } }
        }
        event_attributes["time"] = iso(time) if time
        unless value_cents.nil?
          event_attributes["value"] = (value_cents.to_i / 100.0).round(2)
          event_attributes["value_currency"] = currency.to_s unless currency.to_s.empty?
        end
        event_attributes["unique_id"] = unique_id.to_s unless unique_id.to_s.empty?
        { "data" => { "type" => "event", "attributes" => event_attributes } }
      end

      def klaviyo_profile(profile)
        profile = profile.is_a?(Hash) ? profile : {}
        email = present(profile["email"])
        phone = e164(profile["phone_e164"])
        return nil if email.nil? && phone.nil?

        location = compact(
          "city" => present(profile["city"]), "region" => present(profile["province"]),
          "zip" => present(profile["zip"]), "country" => present(profile["country"])
        )
        compact(
          "email" => email, "phone_number" => phone,
          "first_name" => present(profile["first_name"]), "last_name" => present(profile["last_name"]),
          "location" => location
        )
      end

      # Omnisend v5 custom event. Returns nil without an email or phone.
      def omnisend(event:, profile:, properties:, time: nil, event_id: nil)
        profile = profile.is_a?(Hash) ? profile : {}
        email = present(profile["email"])
        phone = e164(profile["phone_e164"])
        return nil if email.nil? && phone.nil?

        body = {
          "eventName" => event.to_s,
          "origin" => "api",
          "contact" => compact(
            "email" => email, "phone" => phone,
            "firstName" => present(profile["first_name"]), "lastName" => present(profile["last_name"]),
            "city" => present(profile["city"]), "state" => present(profile["province"]),
            "postalCode" => present(profile["zip"]), "country" => present(profile["country"])
          ),
          "properties" => properties.is_a?(Hash) ? properties : {}
        }
        body["eventTime"] = iso(time) if time
        body["eventID"] = event_id.to_s unless event_id.to_s.empty?
        body
      end

      # session: plain Hash (string keys) of a form session.
      def profile_from_session(session)
        session = session.is_a?(Hash) ? session : {}
        contact = hash(session["contact"])
        address = hash(session["address"])
        {
          "email" => contact["email"], "phone_e164" => contact["phone_e164"],
          "first_name" => contact["first_name"], "last_name" => contact["last_name"],
          "city" => address["city"], "province" => address["province"], "zip" => address["zip"],
          "country" => address["country"] || session["country_code"]
        }
      end

      def order_properties(session)
        session = session.is_a?(Hash) ? session : {}
        quote = hash(session["quote_snapshot"])
        attribution = hash(session["attribution"])
        compact(
          "order_id" => present(session["order_id"]),
          "order_name" => present(session["order_name"]),
          "total" => money(session["order_total_cents"] || quote["total_cents"]),
          "currency" => present(session["currency"]) || present(quote["currency"]),
          "subtotal" => money(quote["subtotal_cents"]),
          "discount" => money(quote["discount_total_cents"]),
          "shipping" => money(quote["shipping_cents"]),
          "cod_fee" => money(hash(quote["cod_fee"])["amount_cents"]),
          "discount_code" => present(hash(quote["discount_code"])["code"]),
          "items" => items(quote),
          "item_count" => items(quote).sum { |item| item["quantity"] },
          "payment_method" => "cod",
          "source" => "cod_form",
          "utm_source" => present(attribution["utm_source"]),
          "utm_medium" => present(attribution["utm_medium"]),
          "utm_campaign" => present(attribution["utm_campaign"])
        )
      end

      def abandoned_properties(session, recovery_url:)
        session = session.is_a?(Hash) ? session : {}
        quote = hash(session["quote_snapshot"])
        compact(
          "recovery_url" => present(recovery_url),
          "total" => money(quote["total_cents"]),
          "currency" => present(session["currency"]) || present(quote["currency"]),
          "items" => items(quote),
          "item_count" => items(quote).sum { |item| item["quantity"] },
          "source" => "cod_form"
        )
      end

      def items(quote)
        Array(hash(quote)["lines"]).filter_map do |line|
          next unless line.is_a?(Hash)

          compact(
            "variant_id" => present(line["variant_id"]), "product_id" => present(line["product_id"]),
            "title" => present(line["title"]), "variant_title" => present(line["variant_title"]),
            "image" => present(line["image"]), "quantity" => line["quantity"].to_i,
            "price" => money(line["unit_price_cents"])
          )
        end
      end

      def money(cents)
        cents.nil? ? nil : (cents.to_i / 100.0).round(2)
      end

      def e164(value)
        digits = value.to_s.gsub(/\D/, "").sub(/\A0+/, "")
        digits.length.between?(8, 15) ? "+#{digits}" : nil
      end

      def iso(time)
        time.respond_to?(:utc) ? time.utc.iso8601 : time.to_s
      end

      def present(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def hash(value)
        value.is_a?(Hash) ? value : {}
      end

      def compact(hash)
        hash.reject { |_, v| v.nil? || ((v.is_a?(Hash) || v.is_a?(Array)) && v.empty?) }
      end
    end
  end
end
