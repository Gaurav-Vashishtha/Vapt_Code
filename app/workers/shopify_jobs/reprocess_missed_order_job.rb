module ShopifyJobs
  class ReprocessMissedOrderJob < ApplicationJob
    sidekiq_options queue: 'critical', retry: 2

    def perform(shop_id, order_id)
      shop = Shop.find_by(id: shop_id)
      return unless shop
      return if OrderConfirmation.exists?(shop_id: shop.id, order_id: order_id.to_s)

      shop.init_session
      order = ::ShopifyAPI::Order.find(order_id)
      params = JSON.parse(order.to_json).to_h

      OrderConfirmationCreateJob.new.perform(params, shop.id)
    rescue ActiveResource::ResourceNotFound
      Rails.logger.warn("[ReconcileMissedOrders] order not found on Shopify shop=#{shop_id} order=#{order_id}")
    rescue => e
      Rails.logger.error("[ReconcileMissedOrders] reprocess failed shop=#{shop_id} order=#{order_id}: #{e.class}: #{e.message}")
      raise
    end
  end
end
