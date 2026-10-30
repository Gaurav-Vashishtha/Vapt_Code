module ShopifyJobs
  class OrderShippingStatusSyncParentJob < ApplicationJob
    queue_as :default

    JOB_LOCK_KEY = "order_shipping_status_sync_parent_lock"
    STALE_LOCK_AFTER = 2.hours
    HEARTBEAT_INTERVAL = 2.minutes

    LOOKBACK_DAYS = 14
    COOLDOWN_HOURS = 12

    # Usage:
    # ShopifyJobs::OrderShippingStatusSyncParentJob.perform_async
    def perform
      lock_acquired = nil
      heartbeat_stop = nil
      heartbeat_thread = nil
      begin
        lock_acquired = JobLock.lock!(JOB_LOCK_KEY, stale_after: STALE_LOCK_AFTER)
        return unless lock_acquired

        heartbeat_stop = Concurrent::AtomicBoolean.new(false)
        heartbeat_thread = Thread.new do
          loop do
            break if heartbeat_stop.true?
            sleep(HEARTBEAT_INTERVAL)
            break if heartbeat_stop.true?
            JobLock.touch!(JOB_LOCK_KEY)
          end
        end

        from_time = LOOKBACK_DAYS.days.ago.beginning_of_day
        to_time = Time.current.end_of_day
        cooldown_cutoff = COOLDOWN_HOURS.hours.ago

        shops = Shop
          .joins(:order_confirmations)
          .where(order_confirmations: { created_at: from_time..to_time })
          .where(
            "shops.last_shipping_status_pulled IS NULL OR shops.last_shipping_status_pulled <= ?",
            cooldown_cutoff
          )
          .distinct
          .order(Arel.sql("shops.last_shipping_status_pulled ASC NULLS FIRST"))

        synced_count = 0
        total_updated = 0
        shops.each do |shop|
          result = ShopifyServices::OrderShippingStatusSyncService.call(shop, LOOKBACK_DAYS)
          total_updated += result[:updated].to_i
          synced_count += 1
        end

        Rails.logger.info(
          "[OrderShippingStatusSyncParentJob] Synced #{synced_count} shops, #{total_updated} rows updated, lookback=#{LOOKBACK_DAYS} days, cooldown=#{COOLDOWN_HOURS}h"
        )

        SlackNotifier::CLIENT.ping(
          text: "Shipping status sync (#{Rails.env}): #{synced_count} shops processed, #{total_updated} order confirmations updated (last #{LOOKBACK_DAYS} days)"
        )
    rescue => e
      Rails.logger.error("[OrderShippingStatusSyncParentJob] error=#{e.class}: #{e.message}")
      SlackNotifier::CLIENT.ping(
        text: "Order shipping status parent sync failed (#{Rails.env}): #{e.message}"
      )
      raise e
    ensure
      heartbeat_stop&.make_true
      heartbeat_thread&.join(5)
      JobLock.unlock!(JOB_LOCK_KEY) if lock_acquired
    end
  end
end
end

