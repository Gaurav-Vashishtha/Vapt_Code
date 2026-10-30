module ShopifyJobs
  class OrderShippingStatusSyncJob < ApplicationJob
    queue_as :default

    # Usage:
    # ShopifyJobs::OrderShippingStatusSyncJob.perform_async(54386, 7)
    # days defaults to 7 if omitted
    def perform(shop_id, days = 7)
      shop = Shop.find_by(id: shop_id)
      return unless shop

      result = ShopifyServices::OrderShippingStatusSyncService.call(shop, days)

      Rails.logger.info(
        "[OrderShippingStatusSyncJob] shop_id=#{shop.id} days=#{days} updated=#{result[:updated]} scanned=#{result[:scanned]}"
      )
    rescue => e
      Rails.logger.error("[OrderShippingStatusSyncJob] shop_id=#{shop_id} error=#{e.class}: #{e.message}")
      SlackNotifier::CLIENT.ping(
        text: "Order shipping status sync failed (#{Rails.env}) shop_id=#{shop_id}: #{e.message}"
      )
    end

  end
end
