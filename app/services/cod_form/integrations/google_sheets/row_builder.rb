# frozen_string_literal: true

module CodForm
  module Integrations
    module GoogleSheets
      # Pure builder of one spreadsheet row for a form order (ARCHITECTURE.md I.5, INT-1).
      # In: the merchant's column mapping and the session as a plain Hash (string keys).
      # Out: an Array of cell values in column order. No Rails, no I/O.
      module RowBuilder
        COLUMN_KEYS = %w[
          order_name order_id created_at first_name last_name phone email address1 address2 city province zip
          country items quantity subtotal discount shipping cod_fee total currency shipping_rate discount_code
          utm_source utm_medium utm_campaign note
        ].freeze
        # customer_name appears in the B.18 example mapping; it is first + last name.
        EXTRA_COLUMN_KEYS = %w[customer_name].freeze
        CUSTOM_PREFIX = "custom:"
        DEFAULT_COLUMNS = %w[
          order_name created_at customer_name phone address1 city province zip country items quantity total
          currency shipping_rate cod_fee utm_source utm_campaign
        ].freeze
        MAX_COLUMNS = 60
        MAX_CELL = 2_000

        LABELS = {
          "order_name" => "Order", "order_id" => "Order ID", "created_at" => "Date", "customer_name" => "Customer",
          "first_name" => "First name", "last_name" => "Last name", "phone" => "Phone", "email" => "Email",
          "address1" => "Address", "address2" => "Address line 2", "city" => "City", "province" => "Province",
          "zip" => "Postal code", "country" => "Country", "items" => "Items", "quantity" => "Quantity",
          "subtotal" => "Subtotal", "discount" => "Discount", "shipping" => "Shipping", "cod_fee" => "COD fee",
          "total" => "Total", "currency" => "Currency", "shipping_rate" => "Shipping rate",
          "discount_code" => "Discount code", "utm_source" => "UTM source", "utm_medium" => "UTM medium",
          "utm_campaign" => "UTM campaign", "note" => "Note"
        }.freeze

        module_function

        def valid_column?(key)
          key = key.to_s
          return true if COLUMN_KEYS.include?(key) || EXTRA_COLUMN_KEYS.include?(key)

          key.start_with?(CUSTOM_PREFIX) && key.length > CUSTOM_PREFIX.length
        end

        # Known keys only, order kept, duplicates removed; the default mapping when empty.
        def normalize_columns(columns)
          list = Array(columns).map(&:to_s).select { |key| valid_column?(key) }.uniq.first(MAX_COLUMNS)
          list.empty? ? DEFAULT_COLUMNS.dup : list
        end

        def header(columns)
          normalize_columns(columns).map do |key|
            if key.start_with?(CUSTOM_PREFIX)
              key[CUSTOM_PREFIX.length..]
            else
              LABELS[key] || key
            end
          end
        end

        # session: {"order_id","order_name","ordered_at","order_total_cents","currency","contact",
        #           "address","quote_snapshot","attribution","custom_fields"}
        def build(columns:, session:)
          session = session.is_a?(Hash) ? session : {}
          normalize_columns(columns).map { |key| cell(value_for(key, session)) }
        end

        def value_for(key, session)
          contact = hash(session["contact"])
          address = hash(session["address"])
          quote = hash(session["quote_snapshot"])
          attribution = hash(session["attribution"])
          custom = hash(session["custom_fields"])
          lines = Array(quote["lines"]).select { |line| line.is_a?(Hash) }

          case key
          when "order_name" then session["order_name"]
          when "order_id" then session["order_id"]
          when "created_at" then session["ordered_at"]
          when "customer_name" then [contact["first_name"], contact["last_name"]].map(&:to_s).reject(&:empty?).join(" ")
          when "first_name", "last_name", "email" then contact[key]
          when "phone" then contact["phone_e164"] || contact["phone"]
          when "address1", "address2", "city", "province", "zip", "country" then address[key]
          when "items" then items_text(lines, Array(quote["extra_lines"]))
          when "quantity" then lines.sum { |line| line["quantity"].to_i }
          when "subtotal" then money(quote["subtotal_cents"])
          when "discount" then money(quote["discount_total_cents"])
          when "shipping" then money(quote["shipping_cents"])
          when "cod_fee" then money(hash(quote["cod_fee"])["amount_cents"])
          when "total" then money(session["order_total_cents"] || quote["total_cents"])
          when "currency" then session["currency"] || quote["currency"]
          when "shipping_rate" then shipping_rate_name(hash(quote["shipping"]))
          when "discount_code" then hash(quote["discount_code"])["code"]
          when "utm_source", "utm_medium", "utm_campaign" then attribution[key]
          when "note" then custom["note"] || hash(session["fields"])["note"]
          else
            key.start_with?(CUSTOM_PREFIX) ? custom[key[CUSTOM_PREFIX.length..]] : nil
          end
        end

        def items_text(lines, extra_lines)
          parts = lines.map do |line|
            title = [line["title"], line["variant_title"]].map(&:to_s).reject(&:empty?).join(" - ")
            "#{line['quantity'].to_i} x #{title}"
          end
          extra_lines.each do |line|
            next unless line.is_a?(Hash) && %w[bump gift].include?(line["kind"].to_s)

            parts << "#{line['quantity'].to_i} x #{line['title']}"
          end
          parts.join(", ")
        end

        def shipping_rate_name(shipping)
          selected = shipping["selected_id"]
          rate = Array(shipping["rates"]).find { |r| r.is_a?(Hash) && r["id"].to_s == selected.to_s }
          rate ? rate["name"] : nil
        end

        # Integer cents (amount x 100) -> decimal number; nil stays empty.
        def money(cents)
          return nil if cents.nil?

          (cents.to_i / 100.0).round(2)
        end

        # The sheet is written with valueInputOption=USER_ENTERED, so text typed by a buyer that
        # starts with = + - @ would run as a formula in the merchant's sheet. Such text gets a
        # leading apostrophe, which Sheets shows as plain text (and keeps "+36…" phone numbers).
        def cell(value)
          case value
          when nil then ""
          when Numeric then value
          when true, false then value.to_s
          else
            text = value.to_s.gsub(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/, "")[0, MAX_CELL]
            text.match?(/\A[=+\-@\t\r\n]/) ? "'#{text}" : text
          end
        end

        def hash(value)
          value.is_a?(Hash) ? value : {}
        end
      end
    end
  end
end
