module OfflineJobs
  class EnqueuePartialDiscountAutomaticAppForPartialPaymentShopsJob
    include Sidekiq::Worker

    sidekiq_options queue: :administration, retry: 1

    BATCH_SIZE = 500

    # Enqueues ShopifyJobs::PartialDiscountAutomaticAppJob for every shop
    # where settings.partial_payment_enabled = true.
    #
    # Usage:
    #   OfflineJobs::EnqueuePartialDiscountAutomaticAppForPartialPaymentShopsJob.perform_async
    def perform
      scope = Shop
        .joins(:setting, :order_confirmations)
        .where(settings: { partial_payment_enabled: true })
        .where("order_confirmations.created_at >= ?", 24.hours.ago)
        .distinct

      executed = 0
      processed = 0

      scope.in_batches(of: BATCH_SIZE) do |batch|
        batch.pluck(:id).each do |shop_id|
          ShopifyServices::PartialDiscountAutomaticAppEnsureService.call(shop_id)
          executed += 1
        end
        processed += batch.size

        Rails.logger.info("[OfflineJobs] EnqueuePartialDiscountAutomaticAppForPartialPaymentShopsJob processed=#{processed} executed=#{executed}")
      end

      Rails.logger.info("[OfflineJobs] EnqueuePartialDiscountAutomaticAppForPartialPaymentShopsJob done processed=#{processed} executed=#{executed}")
    end
  end
end

