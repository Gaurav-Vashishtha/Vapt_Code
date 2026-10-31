module ShopifyJobs
  class ProductDestroyJob < ActiveJob::Base

    def perform(shop_id, product_id)
      shop = Shop.find(shop_id)
      ShopifyServices::ProductDeleteService.call(shop, "gid://shopify/Product/#{product_id.gsub("gid://shopify/Product/","")}")
        SlackNotifier::CLIENT.ping(
          text: ":heart: Product destroyed (#{Rails.env}) \n*Store*: #{shop.shopify_domain}",
          channel: ENV.fetch("SLACK_INSTALLS_CHANNEL", nil)
        )
    end
  end
end
