# frozen_string_literal: true

# Wired up via `config.after_authenticate_job` in config/initializers/shopify_app.rb.
# The shopify_app gem invokes this with `shop_domain:` after every successful OAuth
# (initial install, reinstall, scope change). Setting's `after_commit :on: :create`
# only fires for new Settings — this job covers reinstalls where the Setting row
# already exists. SyncShopPixelService is idempotent (update if pixel exists, else create).
module ShopifyJobs
  class AfterAuthenticatePixelSyncJob < ApplicationJob
    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      if shop.blank?
        Rails.logger.warn("[WebPixels] AfterAuthenticatePixelSyncJob skipped — shop_id=#{shop_id} not found")
        return
      end

      Rails.logger.info("[WebPixels] AfterAuthenticatePixelSyncJob start shop=#{shop.shopify_domain}")
      WebPixels::SyncShopPixelService.call(shop: shop)
    end
  end
end
