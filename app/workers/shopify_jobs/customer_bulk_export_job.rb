# frozen_string_literal: true

module ShopifyJobs
  class CustomerBulkExportJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 0

    LOCK_KEY = 'customer_bulk_coordinator_lock'
    LOCK_STALE_AFTER = 3.minutes
    REQUEST_TIMEOUT = 5.minutes
    MAX_RUNNING_AT_SHOPIFY = 12.hours
    NO_PROGRESS_AFTER = 60.minutes
    COMPLETED_EXPIRES_AFTER = 6.days

    def perform
      return unless enabled?
      return unless JobLock.lock!(LOCK_KEY, stale_after: LOCK_STALE_AFTER)

      locked = true
      CustomerSyncControl.beat!
      if CustomerSyncControl.fresh_mode == 'killed'
        stop_everything
        return
      end

      expire_stuck
      poll
      start_new unless CustomerSyncControl.paused?
    rescue StandardError => e
      Rails.logger.error("[CustomerBulkExportJob] #{e.class}: #{e.message}")
      SlackNotifyJob.perform_async("CustomerBulkExportJob (#{Rails.env}) failed: #{e.class}: #{e.message}") rescue nil
    ensure
      JobLock.unlock!(LOCK_KEY) if locked
    end

    private

    def enabled?
      ENV.fetch('CUSTOMER_BULK_EXPORT_ENABLED', 'false').to_s.downcase == 'true'
    end

    def int_env(name, default)
      ENV.fetch(name, default).to_i
    end

    def stop_everything
      CustomerBulkExport.at_shopify.includes(:shop).find_each do |export|
        cancel_at_shopify(export)
        export.fail!('stopped by kill switch', count_failure: false)
      end
    end

    def expire_stuck
      CustomerBulkExport.where(status: 'requested', bulk_operation_gid: nil)
                        .where('updated_at < ?', REQUEST_TIMEOUT.ago)
                        .find_each { |e| e.fail!('request never reached Shopify') }

      CustomerBulkExport.where(status: 'running').where('requested_at < ?', MAX_RUNNING_AT_SHOPIFY.ago).includes(:shop).find_each do |export|
        terminate(export, 'running at Shopify for more than 12 hours')
      end

      CustomerBulkExport.where(status: 'running').where('COALESCE(progress_at, requested_at) < ?', NO_PROGRESS_AFTER.ago).includes(:shop).find_each do |export|
        terminate(export, 'no progress at Shopify for 60 minutes')
      end

      CustomerBulkExport.where(status: 'completed').where('updated_at < ?', COMPLETED_EXPIRES_AFTER.ago).find_each do |export|
        export.fail!('file link close to expiry before it was loaded', count_failure: false)
      end
    end

    def terminate(export, reason)
      cancel_at_shopify(export)
      export.fail!(reason)
      SlackNotifyJob.perform_async("Customer bulk export terminated (#{Rails.env}) #{export.shopify_domain}: #{reason}") rescue nil
    end

    def cancel_at_shopify(export)
      ShopifyServices::CustomerBulkExportService.cancel!(export)
    rescue StandardError => e
      Rails.logger.warn("[CustomerBulkExportJob] cancel export=#{export.id} #{e.class}: #{e.message}")
    end

    def poll
      CustomerBulkExport.at_shopify.where.not(bulk_operation_gid: nil).includes(:shop).find_each do |export|
        ShopifyServices::CustomerBulkExportService.refresh!(export)
      rescue StandardError => e
        Rails.logger.warn("[CustomerBulkExportJob] poll export=#{export.id} #{e.class}: #{e.message}")
      end
    end

    def start_new
      inflight = CustomerBulkExport.at_shopify.count
      staged = CustomerBulkExport.loadable.count
      slots = [int_env('CUSTOMER_BULK_MAX_INFLIGHT', 5) - inflight, int_env('CUSTOMER_BULK_PER_RUN', 5)].min
      slots = 0 if staged >= int_env('CUSTOMER_BULK_MAX_STAGED', 40)
      return if slots <= 0

      CustomerSyncState.plannable(slots).each do |state|
        break if CustomerSyncControl.killed?

        ShopifyServices::CustomerBulkExportService.request(state.shop)
      end
    end
  end
end
