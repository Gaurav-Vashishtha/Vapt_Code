# frozen_string_literal: true

module Churn
  # Redis-backed status + single-flight lock for Churn::ChurnedStoresSyncJob,
  # read by the churn page ("Sync" button + live status).
  module SyncStatus
    STATUS_KEY = 'churn:churned_stores_sync:status'
    LOCK_KEY = 'churn:churned_stores_sync:lock'
    LOCK_TTL = 45 * 60 # seconds; a crashed run frees the lock on its own
    STATUS_TTL = 14 * 24 * 3600

    module_function

    def current
      raw = Sidekiq.redis { |r| r.get(STATUS_KEY) }
      raw ? JSON.parse(raw) : {}
    rescue => e
      Rails.logger.warn("[Churn::SyncStatus] read failed: #{e.message}")
      {}
    end

    def running?
      %w[queued running].include?(current['state']) && locked_or_recent_queue?
    end

    def write(attrs)
      data = current.merge(attrs.transform_keys(&:to_s))
      Sidekiq.redis { |r| r.set(STATUS_KEY, data.to_json, ex: STATUS_TTL) }
      data
    rescue => e
      Rails.logger.warn("[Churn::SyncStatus] write failed: #{e.message}")
      data
    end

    def queued!(days:, triggered_by:)
      Sidekiq.redis do |r|
        r.set(STATUS_KEY, {
          state: 'queued', days: days, triggered_by: triggered_by,
          queued_at: Time.current.iso8601
        }.to_json, ex: STATUS_TTL)
      end
    end

    def acquire_lock(run_id)
      Sidekiq.redis { |r| r.set(LOCK_KEY, run_id, nx: true, ex: LOCK_TTL) } ? true : false
    end

    def refresh_lock(run_id)
      Sidekiq.redis { |r| r.expire(LOCK_KEY, LOCK_TTL) if r.get(LOCK_KEY) == run_id }
    end

    def release_lock(run_id)
      Sidekiq.redis { |r| r.del(LOCK_KEY) if r.get(LOCK_KEY) == run_id }
    end

    def locked?
      Sidekiq.redis { |r| r.get(LOCK_KEY) }.present?
    end

    # A "queued" status whose job never started (worker down, job lost) must
    # not block the button forever.
    def locked_or_recent_queue?
      return true if locked?

      s = current
      s['state'] == 'queued' && s['queued_at'].present? && Time.zone.parse(s['queued_at']) > 15.minutes.ago
    rescue
      false
    end
  end
end
