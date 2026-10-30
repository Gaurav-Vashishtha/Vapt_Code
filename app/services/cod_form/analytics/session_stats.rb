# frozen_string_literal: true

require "date"

module CodForm
  module Analytics
    # Form sessions, live from cod_form_sessions (no rollup job in between): how many buyers
    # opened the form, how many ordered, what the rest did, and the latest sessions.
    #
    #   SessionStats.call(shop, from:, to:, filters: {"country" => "IN", "device" => "mobile"}, recent: 50)
    #
    # Test sessions are left out. Revenue is the sum of the order totals as charged (presentment
    # currency). No buyer details are returned: a session is its time, source, device, country,
    # outcome and amount.
    class SessionStats
      ORDERED = %w[ordered].freeze
      HANDOFF = %w[handoff_partial handoff_prepaid].freeze
      BLOCKED = %w[blocked].freeze
      RECENT_MAX = 100

      class << self
        def call(shop, from: nil, to: nil, filters: {}, recent: 50)
          zone = ShopTime.zone(shop)
          today = Time.current.in_time_zone(zone).to_date
          from, to = Funnel.normalize_range(from, to, today: today)
          filters = filters.is_a?(Hash) ? filters : {}

          scope = CodForm::Session.where(shop_id: shop.id, is_test: false, created_at: ShopTime.range(zone, from, to))
          scope = scope.where(country_code: filters["country"]) if filters["country"].present?
          scope = scope.where(device: filters["device"]) if filters["device"].present?

          day = ActiveRecord::Base.sanitize_sql_array(
            ["DATE(cod_form_sessions.created_at AT TIME ZONE 'UTC' AT TIME ZONE ?)", zone.tzinfo.name]
          )
          rows = scope.group(Arel.sql(day), :status, :source, :device, :country_code).pluck(
            Arel.sql(day), :status, :source, :device, :country_code, Arel.sql("COUNT(*)"),
            Arel.sql("COALESCE(SUM(CASE WHEN cod_form_sessions.order_id IS NOT NULL THEN cod_form_sessions.order_total_cents ELSE 0 END), 0)")
          )

          summarize(rows, from: from, to: to).merge(
            "currency" => shop.currency.to_s,
            "recent" => recent.to_i.positive? ? recent_sessions(scope, [recent.to_i, RECENT_MAX].min) : []
          )
        end

        # rows: [[date, status, source, device, country, sessions, revenue_cents], …]  (pure)
        def summarize(rows, from:, to:)
          totals = blank
          by_day = Hash.new { |hash, key| hash[key] = blank }
          by = { "source" => {}, "device" => {}, "country" => {}, "status" => {} }

          Array(rows).each do |date, status, source, device, country, count, revenue|
            count = count.to_i
            revenue = revenue.to_i
            keys = { "source" => source, "device" => device, "country" => country, "status" => status }
            [totals, by_day[date.to_s], *keys.map { |dimension, value| (by[dimension][label(value)] ||= blank) }].each do |bucket|
              add(bucket, status.to_s, count, revenue)
            end
          end

          {
            "range" => { "from" => from.to_s, "to" => to.to_s },
            "totals" => finish(totals),
            "series" => (from..to).map { |date| finish(by_day[date.to_s]).slice("sessions", "orders", "revenue_cents").merge("date" => date.to_s) },
            "by_source" => table(by["source"]),
            "by_device" => table(by["device"]),
            "by_country" => table(by["country"]),
            "by_status" => by["status"].map { |key, bucket| { "key" => key, "sessions" => bucket["sessions"] } }
                                       .sort_by { |row| -row["sessions"] }
          }
        end

        private

        def blank
          { "sessions" => 0, "orders" => 0, "revenue_cents" => 0, "handoffs" => 0, "blocked" => 0 }
        end

        def label(value)
          value.to_s.strip.empty? ? "unknown" : value.to_s
        end

        def add(bucket, status, count, revenue)
          bucket["sessions"] += count
          bucket["orders"] += count if ORDERED.include?(status)
          bucket["revenue_cents"] += revenue if ORDERED.include?(status)
          bucket["handoffs"] += count if HANDOFF.include?(status)
          bucket["blocked"] += count if BLOCKED.include?(status)
        end

        # Left without an order: everything that neither ordered, went to pay online, nor was blocked.
        def finish(bucket)
          sessions = bucket["sessions"]
          orders = bucket["orders"]
          abandoned = [sessions - orders - bucket["handoffs"] - bucket["blocked"], 0].max
          bucket.merge(
            "conversion_rate" => Funnel.rate(orders, sessions),
            "aov_cents" => orders.positive? ? (bucket["revenue_cents"] / orders.to_f).round : 0,
            "abandoned" => abandoned,
            "abandonment_rate" => Funnel.rate(abandoned, sessions)
          )
        end

        def table(buckets)
          buckets.map { |key, bucket| finish(bucket).slice("sessions", "orders", "conversion_rate", "revenue_cents").merge("key" => key) }
                 .sort_by { |row| -row["sessions"] }.first(12)
        end

        def recent_sessions(scope, limit)
          scope.order(created_at: :desc).limit(limit).pluck(
            :public_id, :created_at, :status, :source, :device, :country_code, :order_name, :order_total_cents, :currency,
            :closes_count, Arel.sql("(cod_form_sessions.quote_snapshot ->> 'total_cents')")
          ).map do |id, at, status, source, device, country, order_name, order_total, currency, closes, quoted|
            {
              "id" => id.to_s[0, 8], "created_at" => at&.utc&.iso8601, "status" => status, "source" => source, "device" => device,
              "country" => country, "order_name" => order_name, "currency" => currency,
              "total_cents" => order_total || (quoted.to_s.match?(/\A\d+\z/) ? quoted.to_i : nil), "closes" => closes.to_i
            }
          end
        end
      end
    end
  end
end
