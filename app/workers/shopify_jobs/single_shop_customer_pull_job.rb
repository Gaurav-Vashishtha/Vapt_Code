module ShopifyJobs
  # ShopifyJobs::SingleShopCustomerPullJob.perform_async(shop_id)
  #
  # Single-shop counterpart to CustomerPullJob — pulls customers for one shop
  # via ShopifyServices::CustomerPullService. Useful for admin-triggered
  # retries, post-install bootstraps, or any spot pull.
  class SingleShopCustomerPullJob < ApplicationJob
    sidekiq_options queue: 'db_backup', retry: false, concurrency: 1

    def perform(shop_id)
      return unless LegacyCustomerPull.enabled?

      shop = Shop.find_by(id: shop_id)
      unless shop
        SlackNotifier::CLIENT.ping(
          text: "SingleShopCustomerPullJob (#{Rails.env}) - shop_id=#{shop_id} not found"
        )
        return
      end

      puts "SingleShopCustomerPullJob started for #{shop.shopify_domain}"
      SlackNotifier::CLIENT.ping(
        text: "SingleShopCustomerPullJob (#{Rails.env}) - Started #{shop.shopify_domain}"
      )

      ShopifyServices::CustomerPullService.call(shop)

      SlackNotifier::CLIENT.ping(
        text: "SingleShopCustomerPullJob (#{Rails.env}) - Done #{shop.shopify_domain}"
      )
    rescue StandardError => e
      SlackNotifier::CLIENT.ping(
        text: ":rage: SingleShopCustomerPullJob (#{Rails.env}) - #{shop&.shopify_domain || "shop_id=#{shop_id}"} - #{e.class}: #{e.message}"
      )
      raise
    end
  end
end
