# frozen_string_literal: true

module ShopifyJobs
  # Job 1: Fetch total customer count from Shopify for each shop (PH/IN), store in shops.customer_count,
  # ensure each shop has a pending queue entry, then enqueue the processor.
  # Schedule this job again when the processor has finished all processable entries (see CustomerPullQueueProcessorJob).
  class CustomerCountSyncJob < ApplicationJob
    queue_as :global_data_pull

    JOB_LOCK_KEY = "customer_count_sync_lock"
    # Consider lock stale after this (no heartbeat for 2h = killed job; long-running job heartbeats so it stays valid)
    STALE_LOCK_AFTER = 2.hours
    HEARTBEAT_INTERVAL = 2.minutes

    COUNTRY_CODES = %w[PH IN].freeze

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

      shops = Shop.where(country_code: COUNTRY_CODES).order(id: :asc)
      return if shops.empty?

      shops.find_each do |shop|
        sync_count_for_shop(shop)
      end

      # Ensure pending queue entries exist (one per shop that doesn't already have pending/processing)
      ensure_queue_entries

      # Kick the processor to work through the queue (ordered by customer_count desc in processor)
      if CustomerPullJobQueue.processable.joins(:shop).where(shops: { country_code: COUNTRY_CODES }).exists?
        ShopifyJobs::CustomerPullQueueProcessorJob.perform_async
      end
      ensure
        heartbeat_stop&.make_true
        heartbeat_thread&.join(5)
        JobLock.unlock!(JOB_LOCK_KEY) if lock_acquired
      end
    end

    private

    def sync_count_for_shop(shop)
      count = ShopifyServices::CustomerCountFetchService.call(shop)
      shop.update_column(:customer_count, count) if count.is_a?(Integer)
    rescue => e
      Rails.logger.warn "[CustomerCountSyncJob] #{shop.shopify_domain}: #{e.message}"
    end

    def ensure_queue_entries
      Shop.where(country_code: COUNTRY_CODES).find_each do |shop|
        next if CustomerPullJobQueue.where(shop_id: shop.id).where(status: %w[pending processing]).exists?

        CustomerPullJobQueue.create!(shop: shop, status: CustomerPullJobQueue.statuses[:pending])
      end
    end
  end
end
