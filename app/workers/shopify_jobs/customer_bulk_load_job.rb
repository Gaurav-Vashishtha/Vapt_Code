# frozen_string_literal: true

module ShopifyJobs
  # Throttled loader for finished Shopify bulk exports (reads Shopify's file link directly). Runs in short slices (default 4 minutes) so a dyno
  # restart loses at most one batch, and re-queues itself while there is work and the window is open.
  #
  # Inert until CUSTOMER_BULK_LOAD_ENABLED=true. Same queue as the pull processor (limit 1), so the
  # two never write to the customer tables at the same time.
  #
  # ENV: OPS_BULK_LOAD_WINDOW="1-7" (IST hours, start incl / end excl; "0-24" = always),
  #      OPS_BULK_LOAD_BATCH=100 rows per batch, OPS_BULK_LOAD_PAUSE_MS=1000 between batches,
  #      OPS_BULK_LOAD_RUN_SECONDS=240 per slice.
  class CustomerBulkLoadJob < ApplicationJob
    queue_as :global_data_pull
    sidekiq_options retry: 0

    LOCK_KEY = 'customer_bulk_load_lock'
    LOCK_STALE_AFTER = 15.minutes
    MAX_LOAD_ATTEMPTS = 20
    NEXT_SLICE_DELAY = 15.seconds
    TZ = 'Asia/Kolkata'

    def perform
      return unless flag_on? && in_window?
      return unless JobLock.lock!(LOCK_KEY, stale_after: LOCK_STALE_AFTER)

      locked = true
      export = next_export
      return unless export

      CustomerBulkExport.where(id: export.id).update_all('load_attempts = load_attempts + 1')
      export.reload
      if export.load_attempts > MAX_LOAD_ATTEMPTS
        export.fail!("gave up loading after #{MAX_LOAD_ATTEMPTS} slices")
        return
      end

      run_slice(export)
      self.class.perform_in(NEXT_SLICE_DELAY) if more_work?
    rescue StandardError => e
      Rails.logger.error("[CustomerBulkLoadJob] #{e.class}: #{e.message}")
      export&.update_columns(error: "#{e.class}: #{e.message}".truncate(1000), updated_at: Time.current)
      SlackNotifyJob.perform_async("CustomerBulkLoadJob (#{Rails.env}) failed: #{e.class}: #{e.message}") rescue nil
    ensure
      JobLock.unlock!(LOCK_KEY) if locked
    end

    private

    def flag_on?
      ENV.fetch('CUSTOMER_BULK_LOAD_ENABLED', 'false').to_s.downcase == 'true'
    end

    def in_window?
      from, to = ENV.fetch('OPS_BULK_LOAD_WINDOW', '1-7').split('-').map(&:to_i)
      hour = Time.current.in_time_zone(TZ).hour
      from <= to ? (hour >= from && hour < to) : (hour >= from || hour < to)
    end

    def run_slice(export)
      deadline = Time.current + ENV.fetch('OPS_BULK_LOAD_RUN_SECONDS', 240).to_i
      keep_going = lambda do
        JobLock.touch!(LOCK_KEY)
        flag_on? && in_window?
      end
      ShopifyServices::CustomerBulkLoader.new(
        export,
        deadline: deadline,
        batch: ENV.fetch('OPS_BULK_LOAD_BATCH', 100).to_i,
        pause: ENV.fetch('OPS_BULK_LOAD_PAUSE_MS', 1000).to_i / 1000.0,
        keep_going: keep_going
      ).run
    end

    def more_work?
      flag_on? && in_window? && CustomerBulkExport.loadable.exists?
    end

    # Resume a half-loaded file first, then paying shops, then most recently active.
    def next_export
      CustomerBulkExport.loadable.joins(:shop).order(Arel.sql(<<~SQL.squish)).first
        CASE WHEN customer_bulk_exports.status = 'loading' THEN 0 ELSE 1 END,
        CASE WHEN shops.charge_id IS NOT NULL AND shops.charge_id <> '' THEN 0 ELSE 1 END,
        shops.last_order_at DESC NULLS LAST,
        customer_bulk_exports.id
      SQL
    end
  end
end
