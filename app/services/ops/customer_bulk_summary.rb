# frozen_string_literal: true

module Ops
  class CustomerBulkSummary
    TZ = Ops::GmvRollup::TZ
    ACTIVE_LIMIT = 25
    FAILURE_LIMIT = 10
    QUEUE_LIMIT = 15
    RECENT_LIMIT = 12
    HEARTBEAT_STALE_AFTER = 180

    def call
      {
        generated_at: Time.current.iso8601,
        control: control,
        config: config,
        totals: totals,
        counts: counts,
        staged_rows_remaining: staged_rows_remaining,
        today: today,
        queue: queue,
        active: active,
        recent_loaded: recent_loaded,
        failures: failures
      }
    end

    private

    def control
      row = CustomerSyncControl.row
      beat = row.coordinator_heartbeat_at
      age = beat ? (Time.current - beat).to_i : nil
      {
        mode: row.mode,
        reason: row.reason,
        changed_by: row.changed_by,
        changed_at: row.changed_at&.iso8601,
        coordinator_age_seconds: age,
        coordinator_alive: !age.nil? && age <= HEARTBEAT_STALE_AFTER
      }
    end

    def config
      from, to = ENV.fetch('OPS_BULK_LOAD_WINDOW', '1-7').split('-').map(&:to_i)
      hour = Time.current.in_time_zone(TZ).hour
      in_window = from <= to ? (hour >= from && hour < to) : (hour >= from || hour < to)
      {
        export_enabled: ENV.fetch('CUSTOMER_BULK_EXPORT_ENABLED', 'false').to_s.downcase == 'true',
        load_enabled: ENV.fetch('CUSTOMER_BULK_LOAD_ENABLED', 'false').to_s.downcase == 'true',
        legacy_pull_enabled: ENV.fetch('LEGACY_CUSTOMER_PULL_ENABLED', 'false').to_s.downcase == 'true',
        load_window: ENV.fetch('OPS_BULK_LOAD_WINDOW', '1-7'),
        in_window_now: in_window,
        batch: ENV.fetch('OPS_BULK_LOAD_BATCH', 100).to_i,
        pause_ms: ENV.fetch('OPS_BULK_LOAD_PAUSE_MS', 1000).to_i
      }
    end

    def totals
      tracked, shopify_total, loaded_total, unloaded_total, backlog, attention = CustomerSyncState.where.not(status: 'disabled').pick(
        Arel.sql('COUNT(*)'),
        Arel.sql('COALESCE(SUM(shopify_customer_count), 0)'),
        Arel.sql('COALESCE(SUM(LEAST(baseline_count, shopify_customer_count)), 0)'),
        Arel.sql('COALESCE(SUM(unloaded_count), 0)'),
        Arel.sql('COUNT(*) FILTER (WHERE unloaded_count > 0)'),
        Arel.sql("COUNT(*) FILTER (WHERE status = 'needs_attention')")
      )
      {
        shops_tracked: tracked.to_i,
        shopify_customers: shopify_total.to_i,
        loaded_customers: loaded_total.to_i,
        unloaded_customers: unloaded_total.to_i,
        loaded_pct: shopify_total.to_i.zero? ? 100.0 : (loaded_total.to_f * 100 / shopify_total).round(1),
        shops_with_backlog: backlog.to_i,
        shops_needing_attention: attention.to_i,
        shops_unreachable: CustomerSyncState.where(status: 'disabled').count
      }
    end

    def counts
      CustomerBulkExport.group(:status).count
    end

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
        shops_processed: done.distinct.count(:shop_id),
        customers_loaded: done.sum(:rows_loaded).to_i,
        rows_failed: done.sum(:rows_failed).to_i
      }
    end

    def queue
      CustomerSyncState.due.with_backlog.by_priority.limit(QUEUE_LIMIT).includes(:shop).map do |state|
        {
          domain: state.shop&.shopify_domain,
          unloaded: state.unloaded_count,
          shopify_customers: state.shopify_customer_count,
          loaded: state.baseline_count,
          status: state.status,
          failures: state.consecutive_failures
        }
      end
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

    def recent_loaded
      CustomerBulkExport.where(status: 'loaded').order(loaded_at: :desc).limit(RECENT_LIMIT).map do |e|
        {
          domain: e.shopify_domain,
          kind: e.since_at ? 'incremental' : 'full',
          loaded: e.rows_loaded,
          failed_rows: e.rows_failed,
          loaded_at: e.loaded_at&.iso8601
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
