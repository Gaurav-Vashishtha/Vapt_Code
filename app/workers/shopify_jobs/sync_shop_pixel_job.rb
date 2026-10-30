# frozen_string_literal: true

module ShopifyJobs
  class SyncShopPixelJob < ApplicationJob
    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      if shop.blank?
        Rails.logger.warn("[WebPixels] SyncShopPixelJob skipped — shop_id=#{shop_id} not found")
        return
      end

      Rails.logger.info("[WebPixels] SyncShopPixelJob start shop=#{shop.shopify_domain}")
      WebPixels::SyncShopPixelService.call(shop: shop)
    end
  end
end
