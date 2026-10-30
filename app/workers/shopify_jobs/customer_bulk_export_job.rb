# frozen_string_literal: true

module ShopifyJobs
  # Every 10 minutes: (1) polls in-flight Shopify bulk exports (the loader picks up finished ones),
  # (2) starts a few new exports for valuable shops from the pending pull queue.
  #
  # Inert until CUSTOMER_BULK_EXPORT_ENABLED=true.
  #
  # ENV (all optional): CUSTOMER_BULK_MAX_INFLIGHT=5 (exports being built at Shopify),
  #   CUSTOMER_BULK_MAX_STAGED=40 (finished exports waiting to be loaded; Shopify's links expire after about a week, so don't outrun the loader),
  #   CUSTOMER_BULK_PER_RUN=5, CUSTOMER_BULK_COUNTRIES="IN,PH", CUSTOMER_BULK_MAX_CUSTOMERS=1000000.
  class CustomerBulkExportJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 0

    MAX_FAILURES_PER_SHOP = 3
    FAILURE_BACKOFF = 1.hour
    STUCK_AFTER = 30.minutes

    def perform
      return unless enabled?

      expire_stuck
      poll
      start_new
    rescue StandardError => e
      Rails.logger.error("[CustomerBulkExportJob] #{e.class}: #{e.message}")
      SlackNotifyJob.perform_async("CustomerBulkExportJob (#{Rails.env}) failed: #{e.class}: #{e.message}") rescue nil
    end

    private

    def enabled?
      ENV.fetch('CUSTOMER_BULK_EXPORT_ENABLED', 'false').to_s.downcase == 'true'
    end

    def int_env(name, default)
      ENV.fetch(name, default).to_i
    end

    # A crash between "row created" and "Shopify answered".
    def expire_stuck
      CustomerBulkExport.where(status: 'requested', bulk_operation_gid: nil)
                        .where('updated_at < ?', STUCK_AFTER.ago)
                        .find_each { |e| e.fail!('request never reached Shopify') }
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

      candidates(slots).each { |shop| ShopifyServices::CustomerBulkExportService.request(shop) }
    end

    # Valuable shops (Shop.pull_worthy) waiting in the pull queue, paying first, then most recently active.
    # Shop customer_count may be unknown (nil): bulk doesn't need it. Known-empty shops are skipped.
    def candidates(limit)
      countries = ENV.fetch('CUSTOMER_BULK_COUNTRIES', 'IN,PH').split(',').map(&:strip)
      max_customers = int_env('CUSTOMER_BULK_MAX_CUSTOMERS', 1_000_000)
      recently_failed = CustomerBulkExport.where(status: 'failed').where('updated_at > ?', FAILURE_BACKOFF.ago).select(:shop_id)
      given_up = CustomerBulkExport.where(status: 'failed').group(:shop_id).having('COUNT(*) >= ?', MAX_FAILURES_PER_SHOP).select(:shop_id)

      rows = CustomerPullJobQueue.processable
        .joins(:shop)
        .merge(ShopifyJobs::CustomerPullQueueProcessorJob.shop_scope)
        .where(shops: { country_code: countries })
        .where('shops.customer_count IS NULL OR (shops.customer_count > 0 AND shops.customer_count <= ?)', max_customers)
        .where.not(shop_id: CustomerBulkExport.active.select(:shop_id))
        .where.not(shop_id: recently_failed)
        .where.not(shop_id: given_up)
        .order(Arel.sql(<<~SQL.squish))
          CASE WHEN shops.charge_id IS NOT NULL AND shops.charge_id <> '' THEN 0 ELSE 1 END,
          shops.last_order_at DESC NULLS LAST,
          customer_pull_job_queues.id
        SQL
        .preload(:shop)
        .limit(limit * 3)
      rows.map(&:shop).uniq(&:id).first(limit)
    end
  end
end
