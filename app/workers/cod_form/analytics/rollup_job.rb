# frozen_string_literal: true

module CodForm
  module Analytics
    # Daily rollups of the form funnel (ARCHITECTURE.md I.1, B.17, ANL-5).
    # sidekiq-cron: hourly at minute 7, queue low.
    #
    #   perform            -> finds the shops with activity and enqueues one job per shop
    #   perform(shop_id)   -> recomputes today and yesterday (shop time zone) for that shop
    #   perform(shop_id, "2026-10-01") -> recomputes one given day (backfill)
    #
    # Recomputing is idempotent: each day is rebuilt from the raw events and the Redis button
    # view counters and upserted on (shop_id, stat_date, dimension, dimension_value).
    class RollupJob < ApplicationJob
      sidekiq_options queue: "low", retry: 2

      ACTIVITY_WINDOW = 50.hours
      MAX_VALUES_PER_DIMENSION = 500

      def perform(shop_id = nil, date = nil)
        return fan_out if shop_id.nil?

        shop = Shop.find_by(id: shop_id)
        return if shop.nil?

        zone = ShopTime.zone(shop)
        today = Time.current.in_time_zone(zone).to_date
        dates = date ? [Date.iso8601(date.to_s)] : [today - 1, today]
        convert = Query::Converter.for(shop)
        dates.each { |day| rollup_day(shop, zone, day, convert) }
      end

      private

      def fan_out
        active_shop_ids.each { |id| self.class.perform_async(id) }
      end

      # Shops with funnel activity in the last three UTC days, from the Redis sets FunnelLogger
      # maintains. Falls back to the events table when Redis cannot answer.
      def active_shop_ids
        today = Time.current.utc.to_date
        keys = [today - 2, today - 1, today].map { |day| CodForm::FunnelLogger.active_shops_key(day) }
        Sidekiq.redis { |redis| keys.flat_map { |key| redis.smembers(key) } }.map(&:to_i).uniq
      rescue StandardError => e
        Rails.logger.warn("[codf/rollup] active shop list failed (#{e.class}); reading the events table")
        FormFunnelEvent.where(event_type: Rollup::EVENT_METRICS.keys)
                       .where("occurred_at >= ?", ACTIVITY_WINDOW.ago)
                       .distinct.pluck(:shop_id)
      end

      def rollup_day(shop, zone, day, convert)
        acc = Rollup::Accumulator.new(convert: convert)
        scope = FormFunnelEvent.where(shop_id: shop.id, event_type: Rollup::EVENT_METRICS.keys,
                                      occurred_at: ShopTime.day_range(zone, day))
        scope.in_batches(of: 5_000) do |batch|
          batch.pluck(:event_type, :session_token, :metadata).each do |type, token, meta|
            acc.add("type" => type, "session" => token, "meta" => meta)
          end
        end
        acc.add_button_views(CodForm::FunnelLogger.button_views(shop.id, day))

        result = Rollup.cap_cardinality(acc.result, limit: MAX_VALUES_PER_DIMENSION)
        return if result.empty?

        now = Time.current
        rows = result.map do |(dimension, value), metrics|
          { shop_id: shop.id, stat_date: day, dimension: dimension, dimension_value: value,
            metrics: metrics, created_at: now, updated_at: now }
        end
        rows.each_slice(500) do |slice|
          CodForm::DailyStat.upsert_all(
            slice,
            unique_by: %i[shop_id stat_date dimension dimension_value],
            update_only: %i[metrics]
          )
        end
      end
    end
  end
end
