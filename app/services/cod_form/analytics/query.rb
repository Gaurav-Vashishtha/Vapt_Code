# frozen_string_literal: true

module CodForm
  module Analytics
    # Read side of the form analytics (ARCHITECTURE.md D.15, B.17, I.1). K.9:
    #
    #   Query.summary(shop, from:, to:, filters: {})    -> analytics#show body
    #   Query.breakdown(shop, by:, from:, to:)          -> analytics#breakdown body
    #   Query.export_rows(shop, from:, to:, filters: {}, by: nil) -> [[header…], [row…], …]
    #   Query.export_csv(...)                            -> String
    #
    # `from` / `to` are Dates or "YYYY-MM-DD" strings in the shop's time zone (default: last
    # 30 days). `filters` keys: "country", "device", "product_id", "compare" (truthy adds
    # "previous"). All hashes returned have string keys, ready for `render json:`.
    #
    # No filter or one filter is answered from cod_form_daily_stats. Two or three filters
    # together are answered from raw form_funnel_events and therefore limited to the last
    # 90 days (B.17); the answer then carries "limited_to_days" => 90.
    class Query
      RAW_RETENTION_DAYS = 90
      FILTER_DIMENSIONS = { "country" => "country", "device" => "device", "product_id" => "product" }.freeze

      class << self
        def summary(shop, from: nil, to: nil, filters: {}, compare: nil)
          filters = normalize_filters(filters)
          filter_compare = filters.delete("compare")
          compare = truthy?(filter_compare) if compare.nil?
          zone = ShopTime.zone(shop)
          today = Time.current.in_time_zone(zone).to_date
          raw = filters.size > 1
          from, to = Funnel.normalize_range(from, to, today: today, earliest: raw ? today - (RAW_RETENTION_DAYS - 1) : nil)

          daily = daily_metrics(shop, zone, from, to, filters)
          total = Rollup.sum(daily.values)
          body = {
            "range" => { "from" => from.to_s, "to" => to.to_s },
            "funnel" => Funnel.steps(total),
            "totals" => Funnel.totals(total),
            "series" => Funnel.series(daily: daily, from: from, to: to),
            "otp" => Funnel.otp(total),
            "offers" => Funnel.offers(total),
            "offer_rows" => offer_rows(shop, from, to),
            "recovery" => Funnel.recovery(total),
            "previous" => nil,
            "currency" => shop.currency.to_s
          }
          body["limited_to_days"] = RAW_RETENTION_DAYS if raw

          if compare
            prev_from, prev_to = Funnel.previous_range(from, to)
            if raw && prev_from < today - (RAW_RETENTION_DAYS - 1)
              body["previous"] = nil
            else
              previous = Rollup.sum(daily_metrics(shop, zone, prev_from, prev_to, filters).values)
              current_totals = body["totals"]
              previous_totals = Funnel.totals(previous)
              body["previous"] = previous_totals.merge(
                "range" => { "from" => prev_from.to_s, "to" => prev_to.to_s },
                "form_opens" => previous["form_opens"].to_i,
                "change" => {
                  "orders" => Funnel.change(current_totals["orders"], previous_totals["orders"]),
                  "revenue_cents" => Funnel.change(current_totals["revenue_cents"], previous_totals["revenue_cents"]),
                  "aov_cents" => Funnel.change(current_totals["aov_cents"], previous_totals["aov_cents"]),
                  "conversion_rate" => Funnel.change(current_totals["conversion_rate"], previous_totals["conversion_rate"])
                }
              )
            end
          end
          body
        end

        def breakdown(shop, by:, from: nil, to: nil, filters: {})
          by = by.to_s
          return { "rows" => [], "by" => by } unless Funnel::BREAKDOWN_DIMENSIONS.include?(by)

          zone = ShopTime.zone(shop)
          today = Time.current.in_time_zone(zone).to_date
          from, to = Funnel.normalize_range(from, to, today: today)

          by_value = Hash.new { |hash, key| hash[key] = [] }
          CodForm::DailyStat.where(shop_id: shop.id, dimension: by, stat_date: from..to)
                            .pluck(:dimension_value, :metrics)
                            .each { |value, metrics| by_value[value] << metrics }
          summed = by_value.transform_values { |list| Rollup.sum(list) }
          {
            "rows" => Funnel.breakdown_rows(by_value: summed, by: by),
            "by" => by,
            "range" => { "from" => from.to_s, "to" => to.to_s },
            "currency" => shop.currency.to_s
          }
        end

        # Per-offer rows of the Offers card. They come from the roll-up's "offer" dimension, so
        # the country / device / product filters do not apply to them.
        def offer_rows(shop, from, to)
          by_value = Hash.new { |hash, key| hash[key] = [] }
          CodForm::DailyStat.where(shop_id: shop.id, dimension: "offer", stat_date: from..to)
                            .pluck(:dimension_value, :metrics)
                            .each { |value, metrics| by_value[value.to_s] << metrics }
          return [] if by_value.empty?

          offers = CodForm::Offer.where(shop_id: shop.id, id: by_value.keys.select { |id| id.match?(/\A\d+\z/) })
                                 .pluck(:id, :name, :offer_type, :status)
                                 .to_h { |id, name, type, status| [id.to_s, { "name" => name, "offer_type" => type, "status" => status }] }
          Funnel.offer_rows(by_value: by_value.transform_values { |list| Rollup.sum(list) }, offers: offers)
        rescue StandardError => e
          Rails.logger.warn("[codf/analytics] offer rows failed shop_id=#{shop.id} #{e.class}")
          []
        end

        # by nil  -> one row per day (all funnel metrics)
        # by set  -> the breakdown rows of that dimension
        def export_rows(shop, from: nil, to: nil, filters: {}, by: nil)
          if by.to_s.empty?
            filters = normalize_filters(filters)
            filters.delete("compare")
            zone = ShopTime.zone(shop)
            today = Time.current.in_time_zone(zone).to_date
            raw = filters.size > 1
            from, to = Funnel.normalize_range(from, to, today: today, earliest: raw ? today - (RAW_RETENTION_DAYS - 1) : nil)
            Funnel.csv_daily_rows(daily: daily_metrics(shop, zone, from, to, filters), from: from, to: to)
          else
            Funnel.csv_breakdown_rows(rows: breakdown(shop, by: by, from: from, to: to)["rows"])
          end
        end

        def export_csv(shop, from: nil, to: nil, filters: {}, by: nil)
          Funnel.to_csv(export_rows(shop, from: from, to: to, filters: filters, by: by))
        end

        private

        # {"2026-10-01" => metrics}
        def daily_metrics(shop, zone, from, to, filters)
          case filters.size
          when 0 then rollup_daily(shop, from, to, "all", "")
          when 1
            key, value = filters.first
            rollup_daily(shop, from, to, FILTER_DIMENSIONS.fetch(key), value)
          else raw_daily(shop, zone, from, to, filters)
          end
        end

        def rollup_daily(shop, from, to, dimension, value)
          CodForm::DailyStat.where(shop_id: shop.id, dimension: dimension, dimension_value: value, stat_date: from..to)
                            .pluck(:stat_date, :metrics)
                            .to_h { |date, metrics| [date.to_s, metrics.is_a?(Hash) ? metrics : {}] }
        end

        # Combined filters: aggregate raw events (last 90 days). Button views are counters, not
        # rows, so they are only available for the days still held in Redis (3 days).
        def raw_daily(shop, zone, from, to, filters)
          scope = FormFunnelEvent.where(shop_id: shop.id, event_type: Rollup::EVENT_METRICS.keys,
                                        occurred_at: ShopTime.range(zone, from, to))
          scope = scope.where("metadata->>'country' = ?", filters["country"]) if filters["country"]
          scope = scope.where("metadata->>'device' = ?", filters["device"]) if filters["device"]
          if filters["product_id"]
            scope = scope.where("metadata->'product_ids' @> ?::jsonb", [filters["product_id"]].to_json)
          end

          convert = Converter.for(shop)
          accumulators = Hash.new { |hash, key| hash[key] = Rollup::Accumulator.new(convert: convert) }
          scope.in_batches(of: 5_000) do |batch|
            batch.pluck(:event_type, :session_token, :metadata, :occurred_at).each do |type, token, meta, at|
              date = at.in_time_zone(zone).to_date.to_s
              accumulators[date].add("type" => type, "session" => token, "meta" => meta)
            end
          end

          (from..to).each do |date|
            next if date < Time.current.in_time_zone(zone).to_date - 2

            views = CodForm::FunnelLogger.button_views(shop.id, date).select do |field, _|
              parts = EventMeta.parse_button_view_field(field)
              (filters["country"].nil? || parts["country"] == filters["country"]) &&
                (filters["device"].nil? || parts["device"] == filters["device"]) &&
                (filters["product_id"].nil? || parts["product_id"] == filters["product_id"])
            end
            accumulators[date.to_s].add_button_views(views) unless views.empty?
          end

          accumulators.transform_values { |acc| acc.result[["all", ""]] || Rollup.zero_metrics }
        end

        def normalize_filters(filters)
          hash = filters.respond_to?(:to_unsafe_h) ? filters.to_unsafe_h : filters
          hash = hash.is_a?(Hash) ? hash.stringify_keys : {}
          out = {}
          country = EventMeta.country(hash["country"])
          out["country"] = country if country
          device = EventMeta.device(hash["device"])
          out["device"] = device if device
          product = hash["product_id"].to_s.strip
          out["product_id"] = product[0, 32] if product.match?(/\A[0-9A-Za-z_-]+\z/)
          out["compare"] = hash["compare"] if hash.key?("compare")
          out
        end

        def truthy?(value)
          [true, 1, "1", "true", "yes", "on"].include?(value)
        end
      end

      # Presentment cents -> shop-currency cents (B.17), with the rates the app already uses.
      # Amounts stay "amount x 100" for every currency (0.1), so only the rate is applied.
      # When a rate is unavailable the amount is kept as is and one warning is logged.
      class Converter
        def self.for(shop)
          new(shop.currency.to_s.upcase).to_proc
        end

        def initialize(shop_currency)
          @shop_currency = shop_currency
          @rates = {}
          @installed = false
        end

        def to_proc
          method(:convert).to_proc
        end

        def convert(cents, currency)
          currency = currency.to_s.upcase
          return cents if currency.empty? || @shop_currency.empty? || currency == @shop_currency

          rate = (@rates[currency] ||= lookup(currency))
          rate == :none ? cents : (cents * rate).round
        end

        private

        def lookup(currency)
          unless @installed
            ExchangeRateBank.install!
            @installed = true
          end
          rate = Money.default_bank.get_rate(currency, @shop_currency)
          if rate.nil?
            to_usd = Money.default_bank.get_rate(currency, "USD")
            from_usd = Money.default_bank.get_rate("USD", @shop_currency)
            rate = to_usd * from_usd if to_usd && from_usd
          end
          return rate.to_f if rate

          Rails.logger.warn("[codf/analytics] no exchange rate #{currency}->#{@shop_currency}; revenue kept unconverted")
          :none
        rescue StandardError => e
          Rails.logger.warn("[codf/analytics] exchange rate lookup failed #{currency}->#{@shop_currency}: #{e.class}")
          :none
        end
      end
    end
  end
end
