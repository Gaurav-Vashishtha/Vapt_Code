module ShopifyJobs
  class CustomerPullQueueProcessorJob < ApplicationJob
    queue_as :global_data_pull
    JOB_LOCK_KEY = 'customer_pull_lock'
    # Consider lock stale after this (no heartbeat for 2h = killed job; long-running job heartbeats so it stays valid)
    STALE_LOCK_AFTER = 2.hours
    HEARTBEAT_INTERVAL = 2.minutes

    # Only pull shops worth the capacity (see Shop.pull_worthy). Turn off with CUSTOMER_PULL_VALUE_FILTER=false.
    def self.shop_scope
      ENV.fetch('CUSTOMER_PULL_VALUE_FILTER', 'true').to_s.downcase == 'false' ? Shop.all : Shop.pull_worthy
    end

    def perform
      lock_acquired = nil
      heartbeat_stop = nil
      heartbeat_thread = nil
      begin
        # Atomic lock acquisition. Stale = no heartbeat for STALE_LOCK_AFTER (killed jobs). Long runs use heartbeat below.
        lock_acquired = JobLock.lock!(JOB_LOCK_KEY, stale_after: STALE_LOCK_AFTER)
        return unless lock_acquired

        # Keep lock "fresh" so a run longer than 2h isn't treated as stale (only truly dead jobs get cleared)
        heartbeat_stop = Concurrent::AtomicBoolean.new(false)
        stop_requested = Concurrent::AtomicBoolean.new(false) # set when entry is marked cancelled in DB (force-stop)
        heartbeat_thread = nil

        # Pick next shop only from shops with known positive customer_count (> 0).
        # This ignores shops where customer_count is nil/unavailable or zero.
        entry = CustomerPullJobQueue.processable
          .joins(:shop)
          .merge(self.class.shop_scope)
          .where.not(shop_id: CustomerBulkExport.active.select(:shop_id)) # shop has a bulk export in flight
          .where(shops: { country_code: %w[PH IN] })
          .where("shops.customer_count > 0")
          .order(Arel.sql(<<~SQL.squish))
            CASE
              WHEN shops.initial_customer_pull_completed IS NULL THEN 0
              ELSE 1
            END,
            shops.initial_customer_pull_completed ASC NULLS LAST,
            COALESCE(shops.customer_count, -1) DESC
          SQL
          .first
        return unless entry

        entry.update!(status: 'processing')
        entry_id = entry.id

        heartbeat_thread = Thread.new do
          loop do
            break if heartbeat_stop.true?
            sleep(HEARTBEAT_INTERVAL)
            break if heartbeat_stop.true?
            # Force-stop: if admin set this entry to cancelled, stop applying side effects when we finish
            if CustomerPullJobQueue.find_by(id: entry_id)&.cancelled?
              stop_requested.make_true
              break
            end
            JobLock.touch!(JOB_LOCK_KEY)
          end
        end

        shop = entry.shop
        unless shop
          entry.update!(status: 'failed', error_message: 'Shop not found')
          return
        end

        # Incremental pull: only customers updated/created after initial_customer_pull_completed
        since = shop.initial_customer_pull_completed
        ShopifyServices::CustomerPullService.call(shop, { since: since })

        if stop_requested.true?
          entry.reload
          entry.update!(status: 'cancelled') unless entry.cancelled?
          # Don't update shop completion time or Slack; treat as force-stopped
        else
          shop.update(initial_customer_pull_completed: Time.current)
          entry.update!(status: 'done')
          # A Slack failure (e.g. 429) must never mark a finished pull as failed.
          begin
            SlackNotifier::CLIENT.ping("✅ Pulled customers for #{shop.shopify_domain}")
          rescue => slack_error
            Rails.logger.warn("[CustomerPullQueueProcessorJob] slack ping failed for #{shop.shopify_domain}: #{slack_error.class}: #{slack_error.message}")
          end
        end

      rescue => e
        if defined?(entry) && entry
          entry.reload
          entry.update!(status: 'failed', error_message: e.message) unless entry.cancelled?
        end
      ensure
        heartbeat_stop&.make_true
        heartbeat_thread&.join(5)
        # Only unlock if we actually acquired the lock
        JobLock.unlock!(JOB_LOCK_KEY) if lock_acquired
        # Re-enqueue processor if more processable entries exist; otherwise schedule Job 1 (count sync + queue refill)
        if lock_acquired
          if CustomerPullJobQueue.processable
              .joins(:shop)
              .merge(self.class.shop_scope)
              .where.not(shop_id: CustomerBulkExport.active.select(:shop_id)) # shop has a bulk export in flight
              .where(shops: { country_code: %w[PH IN] })
              .where("shops.customer_count > 0")
              .exists?
            ShopifyJobs::CustomerPullQueueProcessorJob.perform_async
          else
            ShopifyJobs::CustomerCountSyncJob.perform_async
          end
        end
      end
    end
  end
end