# frozen_string_literal: true

# Plain Ruby (tests) loads the sibling itself; under Rails Zeitwerk autoloads it.
require_relative "event_map" unless defined?(::Rails)

module CodForm
  module Tracking
    # Turns a form session (plain Hash with string keys, i.e. CodForm::Session#as_json plus the
    # PII columns) into the vendor-neutral event hash the payload builders consume.
    # Pure Ruby: no Rails, no I/O. Output never goes to a log.
    module EventBuilder
      module_function

      # session: {"public_id","client_id","contact","address","tracking","attribution",
      #           "quote_snapshot","order_id","order_name","order_total_cents","currency",
      #           "country_code","ip","user_agent"}
      # now: Integer epoch seconds.
      def build(session:, moment:, now:)
        session = session.is_a?(Hash) ? session : {}
        quote = hash(session["quote_snapshot"])
        contact = hash(session["contact"])
        address = hash(session["address"])
        tracking = hash(session["tracking"])
        attribution = hash(session["attribution"])

        contents = contents_from(quote)
        value_cents =
          if moment.to_s == EventMap::MOMENT_PURCHASE && !session["order_total_cents"].nil?
            session["order_total_cents"].to_i
          else
            quote["total_cents"].to_i
          end

        {
          "moment" => moment.to_s,
          "event_time" => now.to_i,
          "session_id" => session["public_id"].to_s,
          "order_id" => str(session["order_id"]),
          "order_name" => str(session["order_name"]),
          "value_cents" => value_cents,
          "currency" => (str(session["currency"]) || str(quote["currency"]) || "").upcase,
          "shipping_cents" => quote["shipping_cents"].to_i,
          "tax_cents" => hash(quote["tax"])["amount_cents"].to_i,
          "coupon" => str(hash(quote["discount_code"])["code"]),
          "contents" => contents,
          "num_items" => contents.sum { |c| c["quantity"] },
          "page_url" => str(tracking["page_url"]),
          "user" => {
            "email" => str(contact["email"]),
            "phone_e164" => str(contact["phone_e164"]),
            "first_name" => str(contact["first_name"]),
            "last_name" => str(contact["last_name"]),
            "city" => str(address["city"]),
            "province" => str(address["province"]),
            "zip" => str(address["zip"]),
            "country" => str(address["country"]) || str(session["country_code"]),
            "external_id" => str(session["client_id"]) || str(session["public_id"]),
            "ip" => str(session["ip"]),
            "user_agent" => str(tracking["user_agent"]) || str(session["user_agent"]),
            "fbp" => str(tracking["fbp"]),
            "fbc" => str(tracking["fbc"]) || fbc_from_click_id(attribution["fbclid"], now),
            "ttp" => str(tracking["ttp"]),
            "ttclid" => str(tracking["ttclid"]) || str(attribution["ttclid"]),
            "ga_client_id" => str(tracking["ga_client_id"]),
            "ga_session_id" => str(tracking["ga_session_id"]),
            "sc_cookie1" => str(tracking["scid"]) || str(tracking["sc_cookie1"]),
            "sccid" => str(tracking["sccid"]) || str(attribution["sccid"]),
            "epik" => str(tracking["epik"]) || str(attribution["epik"]),
            "gclid" => str(attribution["gclid"])
          },
          "attribution" => attribution,
          "consent" => consent_from(tracking)
        }
      end

      # Product lines of the stored quote (D.2). Content ids are variant ids, the same ids the
      # order response hands to the browser pixels (D.6 "events.content_ids").
      def contents_from(quote)
        lines = quote["lines"].is_a?(Array) ? quote["lines"] : []
        lines.filter_map do |line|
          next unless line.is_a?(Hash)

          id = str(line["variant_id"])
          quantity = line["quantity"].to_i
          next if id.nil? || quantity <= 0

          unit =
            if line["line_total_cents"].nil?
              line["unit_price_cents"].to_i
            else
              (line["line_total_cents"].to_i / quantity.to_f).round
            end
          {
            "id" => id,
            "product_id" => str(line["product_id"]),
            "title" => str(line["title"]),
            "quantity" => quantity,
            "price_cents" => unit
          }
        end
      end

      # tracking.consent as sent by the storefront (G.8). A missing value means "allowed":
      # the storefront sends all three as true when Shopify's privacy API is absent.
      def consent_from(tracking)
        raw = hash(hash(tracking)["consent"])
        {
          "analytics" => raw["analytics"] != false,
          "marketing" => raw["marketing"] != false,
          "sale_of_data" => raw["sale_of_data"] != false
        }
      end

      def fbc_from_click_id(fbclid, now)
        id = str(fbclid)
        return nil if id.nil?

        "fb.1.#{now.to_i * 1000}.#{id}"
      end

      def hash(value)
        value.is_a?(Hash) ? value : {}
      end

      def str(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
