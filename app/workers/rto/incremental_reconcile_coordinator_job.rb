# frozen_string_literal: true

module Rto
  # Enqueues incremental order sync (by Shopify `updated_at`) for active shop domains.
  # Picks domains by oldest `last_reconciled_at` first (NULLs first) so reconciliation
  # is distributed fairly instead of repeatedly favoring low ids.
  class IncrementalReconcileCoordinatorJob
    include Sidekiq::Job
    sidekiq_options queue: :low, retry: 3

    LOCK_NAME = "rto_incremental_reconcile_coordinator"
    STALE_AFTER = 30.minutes

    BATCH = 500

    def perform(_after_shop_domain_id = 0)
      return unless JobLock.lock!(LOCK_NAME, stale_after: STALE_AFTER)

      begin
        active_leases = ReconcileLeaseManager.active_count
        slots = [BackfillLeaseManager.parallelism - active_leases, 0].max
        return if slots <= 0

        scope = ShopDomain
          .joins("INNER JOIN shops ON shops.shopify_domain = shop_domains.shopify_domain")
          .order(Arel.sql("COALESCE(shop_domains.last_reconciled_at, '1970-01-01') ASC"), :id)
          .limit(BATCH)
        ids = scope.pluck(:id)
        return if ids.empty?

        enqueued = 0

        ids.each do |sdid|
          break if enqueued >= slots

          sd = ShopDomain.find_by(id: sdid)
          next if sd.blank?

          ReconcileShopDomainJob.perform_async(sd.id)
          enqueued += 1
        end
      ensure
        JobLock.unlock!(LOCK_NAME)
      end
    end
  end
end
