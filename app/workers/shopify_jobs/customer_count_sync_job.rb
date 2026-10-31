# frozen_string_literal: true

module ShopifyJobs
  class CustomerCountSyncJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 0

    LOCK_KEY = 'customer_count_sync_lock'
    LOCK_STALE_AFTER = 30.minutes
    SPREAD_SECONDS = 0.15
    UNREACHABLE_RECHECK_AFTER = 7.days

    def perform
      return if CustomerSyncControl.killed?
      return unless JobLock.lock!(LOCK_KEY, stale_after: LOCK_STALE_AFTER)

      begin
        recently_unreachable = CustomerSyncState.where(status: 'disabled').where('updated_at > ?', UNREACHABLE_RECHECK_AFTER.ago).select(:shop_id)
        shop_ids = CustomerSyncState.sync_scope.where.not(id: recently_unreachable).order(:id).pluck(:id)
        CustomerSyncState.where.not(shop_id: CustomerSyncState.sync_scope.select(:id)).where.not(status: 'disabled')
                         .update_all(status: 'disabled', last_error: 'no longer an active install', updated_at: Time.current)
        shop_ids.each_with_index do |shop_id, index|
          CustomerCountShopJob.perform_in(index * SPREAD_SECONDS, shop_id)
        end
      ensure
        JobLock.unlock!(LOCK_KEY)
      end
    end
  end
end
