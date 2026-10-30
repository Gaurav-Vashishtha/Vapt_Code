module ShopifyJobs
  class SyncDiscountToShopifyJob < ApplicationJob
    sidekiq_options queue: :scheduled_report_delivery, retry: 3

    # Background wrapper around Discount#sync_to_shopify! (used by the synchronous
    # controller path). Kept for optional background/bulk re-syncs.
    def perform(discount_id)
      discount = Discount.find_by(id: discount_id)
      return unless discount

      result = discount.sync_to_shopify!
      Rails.logger.info("[SyncDiscountToShopifyJob] shop=#{discount.shop&.shopify_domain} discount=#{discount.id} ok=#{result[:ok]} error=#{result[:error]}")
    end
  end
end
