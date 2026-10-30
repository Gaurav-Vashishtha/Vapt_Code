# frozen_string_literal: true

module Rto
  class BackfillCoordinatorJob
    include Sidekiq::Job
    sidekiq_options queue: :low, retry: 3

    LOCK_NAME = "rto_backfill_coordinator"
    STALE_AFTER = 30.minutes

    def perform(_after_shop_domain_id = 0)
      return unless JobLock.lock!(LOCK_NAME, stale_after: STALE_AFTER)

      begin
        active_leases = BackfillLease.where("expires_at >= ?", Time.current).count
        slots = [Rto::BackfillLeaseManager.parallelism - active_leases, 0].max
        return if slots <= 0

        # Pick least-recently-attempted domains first (never attempted first), skip completed
        # and domains in the 5-day backoff window.
        scope = ShopDomain.where(backfill_completed_at: nil)
        scope = scope.where("backfill_next_retry_at IS NULL OR backfill_next_retry_at <= ?", Time.current)

        ids = scope
          .order(Arel.sql("COALESCE(backfill_last_attempt_at, '1970-01-01'::timestamp) ASC"), :id)
          .limit(slots)
          .pluck(:id)

        ids.each { |sdid| BackfillShopDomainJob.perform_async(sdid) }
      ensure
        JobLock.unlock!(LOCK_NAME)
      end
    end
  end
end

