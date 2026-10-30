# frozen_string_literal: true

module Ops
  # Progress of the Shopify bulk customer import for /codk-ops. customer_bulk_exports is a small
  # table (one row per shop export); nothing here touches customers/customer_addresses.
  class CustomerBulkSummary
    TZ = Ops::GmvRollup::TZ
    ACTIVE_LIMIT = 25
    FAILURE_LIMIT = 10

    def call
      {
        config: config,
        counts: counts,
        pending_queue: CustomerPullJobQueue.where(status: 'pending').count,
        staged_rows_remaining: staged_rows_remaining,
        today: today,
        active: active,
        failures: failures
      }
    end

    private

    def config
      from, to = ENV.fetch('OPS_BULK_LOAD_WINDOW', '1-7').split('-').map(&:to_i)
      hour = Time.current.in_time_zone(TZ).hour
      in_window = from <= to ? (hour >= from && hour < to) : (hour >= from || hour < to)
      {
        export_enabled: ENV.fetch('CUSTOMER_BULK_EXPORT_ENABLED', 'false').to_s.downcase == 'true',
        load_enabled: ENV.fetch('CUSTOMER_BULK_LOAD_ENABLED', 'false').to_s.downcase == 'true',
        load_window: ENV.fetch('OPS_BULK_LOAD_WINDOW', '1-7'),
        in_window_now: in_window,
        batch: ENV.fetch('OPS_BULK_LOAD_BATCH', 100).to_i,
        pause_ms: ENV.fetch('OPS_BULK_LOAD_PAUSE_MS', 1000).to_i
      }
    end

    def counts
      CustomerBulkExport.group(:status).count
    end

    # Customers in finished Shopify exports that are not loaded yet.
    def staged_rows_remaining
      CustomerBulkExport.where(status: CustomerBulkExport::LOADABLE)
                        .sum(Arel.sql('GREATEST(COALESCE(object_count, 0) - rows_loaded, 0)')).to_i
    end

    def today
      zone = ActiveSupport::TimeZone[TZ]
      start = zone.local(zone.today.year, zone.today.month, zone.today.day).utc
      done = CustomerBulkExport.where(status: 'loaded').where('loaded_at >= ?', start)
      {
        exports_loaded: done.count,
        customers_loaded: done.sum(:rows_loaded).to_i,
        rows_failed: done.sum(:rows_failed).to_i
      }
    end

    def active
      CustomerBulkExport.active.order(updated_at: :desc).limit(ACTIVE_LIMIT).map do |e|
        total = e.object_count.to_i
        {
          domain: e.shopify_domain,
          status: e.status,
          kind: e.since_at ? 'incremental' : 'full',
          customers: e.object_count,
          loaded: e.rows_loaded,
          pct: total.positive? ? [(e.rows_loaded * 100.0 / total).round(1), 100].min : nil,
          failed_rows: e.rows_failed,
          requested_at: e.requested_at&.iso8601,
          error: e.error
        }
      end
    end

    def failures
      CustomerBulkExport.where(status: 'failed').order(updated_at: :desc).limit(FAILURE_LIMIT).map do |e|
        { domain: e.shopify_domain, at: e.updated_at.iso8601, error: e.error }
      end
    end
  end
end
