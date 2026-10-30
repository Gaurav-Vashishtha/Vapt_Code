# frozen_string_literal: true

require "date"
# Plain Ruby (tests) loads the sibling itself; under Rails Zeitwerk autoloads it.
require_relative "rollup" unless defined?(::Rails)

module CodForm
  module Analytics
    # Pure shaping of rollup metrics into the JSON the admin analytics endpoints promise
    # (ARCHITECTURE.md D.15: analytics#show, #breakdown, #export). No Rails, no I/O.
    # Rates are percentages 0..100 with two decimals (0.1: "Percentages are numbers 0..100").
    module Funnel
      STEPS = %w[button_views form_opens first_inputs shipping_selected submit_attempts orders].freeze
      BREAKDOWN_DIMENSIONS = %w[utm_campaign offer country device product form].freeze
      MAX_RANGE_DAYS = 366
      CSV_DAILY_COLUMNS = %w[
        date button_views form_opens first_inputs shipping_selected submit_attempts submit_errors orders
        revenue conversion_rate aov partial_handoffs prepaid_redirects closes otp_sent otp_verified
        offer_views offer_accepts downsell_shown downsell_accepts upsell_views upsell_accepts
        recovery_opens recovered_orders blocked fallbacks
      ].freeze
      CSV_BREAKDOWN_COLUMNS = %w[key form_opens orders revenue conversion_rate].freeze

      module_function

      # [{"step" => "button_views", "count" => 0}, …]
      def steps(metrics)
        metrics = metrics.is_a?(Hash) ? metrics : {}
        STEPS.map { |step| { "step" => step, "count" => metrics[step].to_i } }
      end

      # {"orders","revenue_cents","aov_cents","conversion_rate","prepaid_redirects","partial_handoffs"}
      def totals(metrics)
        metrics = metrics.is_a?(Hash) ? metrics : {}
        orders = metrics["orders"].to_i
        revenue = metrics["revenue_cents"].to_i
        {
          "orders" => orders,
          "revenue_cents" => revenue,
          "aov_cents" => orders.positive? ? (revenue / orders.to_f).round : 0,
          "conversion_rate" => rate(orders, metrics["form_opens"].to_i),
          "prepaid_redirects" => metrics["prepaid_redirects"].to_i,
          "partial_handoffs" => metrics["partial_handoffs"].to_i
        }
      end

      # ANL-3 OTP stats.
      def otp(metrics)
        metrics = metrics.is_a?(Hash) ? metrics : {}
        sent = metrics["otp_sent"].to_i
        verified = metrics["otp_verified"].to_i
        {
          "sent" => sent,
          "verified" => verified,
          "bypassed" => metrics["otp_bypassed"].to_i,
          "verification_rate" => rate(verified, sent)
        }
      end

      # ANL-3 recovery stats.
      def recovery(metrics)
        metrics = metrics.is_a?(Hash) ? metrics : {}
        opens = metrics["recovery_opens"].to_i
        recovered = metrics["recovered_orders"].to_i
        { "recovery_opens" => opens, "recovered_orders" => recovered, "recovery_rate" => rate(recovered, opens) }
      end

      # ANL-3 offer stats.
      def offers(metrics)
        metrics = metrics.is_a?(Hash) ? metrics : {}
        {
          "offer_views" => metrics["offer_views"].to_i,
          "offer_accepts" => metrics["offer_accepts"].to_i,
          "offer_accept_rate" => rate(metrics["offer_accepts"].to_i, metrics["offer_views"].to_i),
          "downsell_shown" => metrics["downsell_shown"].to_i,
          "downsell_accepts" => metrics["downsell_accepts"].to_i,
          "downsell_accept_rate" => rate(metrics["downsell_accepts"].to_i, metrics["downsell_shown"].to_i),
          "upsell_views" => metrics["upsell_views"].to_i,
          "upsell_accepts" => metrics["upsell_accepts"].to_i,
          "upsell_accept_rate" => rate(metrics["upsell_accepts"].to_i, metrics["upsell_views"].to_i)
        }
      end

      # One row per offer for the Offers card.
      #   by_value: {"<offer id>" => metrics} (roll-up dimension "offer")
      #   offers:   {"<offer id>" => {"name", "offer_type", "status"}} (offers that still exist)
      # Rows: {"id","name","offer_type","status","views","accepts","accept_rate","orders","revenue_cents"}
      # ("name" nil = the offer was deleted). Most shown first.
      def offer_rows(by_value:, offers: {}, limit: 100)
        offers = offers.is_a?(Hash) ? offers : {}
        rows = (by_value.is_a?(Hash) ? by_value : {}).map do |id, metrics|
          metrics = metrics.is_a?(Hash) ? metrics : {}
          offer = offers[id.to_s].is_a?(Hash) ? offers[id.to_s] : {}
          views = metrics["offer_views"].to_i + metrics["downsell_shown"].to_i + metrics["upsell_views"].to_i
          accepts = metrics["offer_accepts"].to_i + metrics["downsell_accepts"].to_i + metrics["upsell_accepts"].to_i
          {
            "id" => id.to_s, "name" => offer["name"], "offer_type" => offer["offer_type"], "status" => offer["status"],
            "views" => views, "accepts" => accepts, "accept_rate" => rate(accepts, views),
            "orders" => metrics["orders"].to_i, "revenue_cents" => metrics["revenue_cents"].to_i
          }
        end
        rows.reject { |row| row["views"].zero? && row["accepts"].zero? && row["orders"].zero? }
            .sort_by { |row| [-row["views"], -row["accepts"], -row["orders"], row["id"]] }.first(limit)
      end

      # daily: {"2026-10-01" => metrics}. Every date of the range appears once, in order.
      # [{"date","form_opens","orders","revenue_cents"}]
      def series(daily:, from:, to:)
        daily = daily.is_a?(Hash) ? daily : {}
        dates(from, to).map do |date|
          metrics = daily[date.to_s] || {}
          {
            "date" => date.to_s,
            "form_opens" => metrics["form_opens"].to_i,
            "orders" => metrics["orders"].to_i,
            "revenue_cents" => metrics["revenue_cents"].to_i
          }
        end
      end

      # The period of the same length that ends the day before `from`.
      def previous_range(from, to)
        from = to_date(from)
        to = to_date(to)
        length = (to - from).to_i + 1
        [from - length, from - 1]
      end

      # Normalises a requested range: Dates in order, not after `today`, at most `max_days`
      # long, and not before `earliest` when one is given (raw events: last 90 days).
      # Defaults to the last 30 days.
      def normalize_range(from, to, today:, max_days: MAX_RANGE_DAYS, earliest: nil)
        today = to_date(today)
        to = to_date(to) || today
        to = today if to > today
        from = to_date(from) || (to - 29)
        from, to = to, from if from > to
        from = to - (max_days - 1) if (to - from).to_i + 1 > max_days
        if earliest
          earliest = to_date(earliest)
          from = earliest if from < earliest
          to = from if to < from
        end
        [from, to]
      end

      # by_value: {"HU" => metrics}. Sorted by orders, then form opens, then key.
      # [{"key","form_opens","orders","revenue_cents","conversion_rate"}] (+ offer counters for offers)
      def breakdown_rows(by_value:, by: nil, limit: 200)
        rows = (by_value.is_a?(Hash) ? by_value : {}).map do |key, metrics|
          metrics = metrics.is_a?(Hash) ? metrics : {}
          row = {
            "key" => key.to_s,
            "form_opens" => metrics["form_opens"].to_i,
            "orders" => metrics["orders"].to_i,
            "revenue_cents" => metrics["revenue_cents"].to_i,
            "conversion_rate" => rate(metrics["orders"].to_i, metrics["form_opens"].to_i)
          }
          if by.to_s == "offer"
            views = metrics["offer_views"].to_i + metrics["downsell_shown"].to_i + metrics["upsell_views"].to_i
            accepts = metrics["offer_accepts"].to_i + metrics["downsell_accepts"].to_i + metrics["upsell_accepts"].to_i
            row["views"] = views
            row["accepts"] = accepts
            row["accept_rate"] = rate(accepts, views)
          end
          row
        end
        rows.sort_by { |row| [-row["orders"], -row["form_opens"], -row["views"].to_i, row["key"]] }.first(limit)
      end

      # CSV rows (header first) for the daily export. Money columns are decimal amounts.
      def csv_daily_rows(daily:, from:, to:)
        daily = daily.is_a?(Hash) ? daily : {}
        rows = [CSV_DAILY_COLUMNS.dup]
        dates(from, to).each do |date|
          metrics = daily[date.to_s] || {}
          sums = totals(metrics)
          rows << CSV_DAILY_COLUMNS.map do |column|
            case column
            when "date" then date.to_s
            when "revenue" then money(metrics["revenue_cents"])
            when "aov" then money(sums["aov_cents"])
            when "conversion_rate" then sums["conversion_rate"]
            else metrics[column].to_i
            end
          end
        end
        rows
      end

      def csv_breakdown_rows(rows:)
        out = [CSV_BREAKDOWN_COLUMNS.dup]
        Array(rows).each do |row|
          out << [safe_cell(row["key"]), row["form_opens"].to_i, row["orders"].to_i, money(row["revenue_cents"]),
                  row["conversion_rate"]]
        end
        out
      end

      # RFC 4180 text for rows of cells.
      def to_csv(rows)
        Array(rows).map do |row|
          row.map do |cell|
            text = cell.to_s
            text.match?(/[",\r\n]/) ? "\"#{text.gsub('"', '""')}\"" : text
          end.join(",")
        end.join("\n") + "\n"
      end

      # Buyer-influenced text (utm_campaign) must not become a spreadsheet formula.
      def safe_cell(value)
        text = value.to_s
        text.match?(/\A[=+\-@\t\r]/) ? "'#{text}" : text
      end

      # Percentage 0..100, two decimals; 0.0 when the base is 0.
      def rate(numerator, denominator)
        return 0.0 unless denominator.to_i.positive?

        (numerator.to_i * 100.0 / denominator.to_i).round(2)
      end

      # Change of `current` against `previous`, in percent; nil when there is no base.
      def change(current, previous)
        return nil unless previous.to_f.positive?

        ((current.to_f - previous.to_f) * 100.0 / previous.to_f).round(2)
      end

      def money(cents)
        format("%.2f", cents.to_i / 100.0)
      end

      def dates(from, to)
        from = to_date(from)
        to = to_date(to)
        return [] if from.nil? || to.nil? || from > to

        (from..to).to_a
      end

      def to_date(value)
        return value if value.is_a?(Date) && !value.is_a?(DateTime)
        return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)
        return nil if value.nil? || value.to_s.strip.empty?

        Date.iso8601(value.to_s.strip[0, 10])
      rescue ArgumentError
        nil
      end
    end
  end
end
