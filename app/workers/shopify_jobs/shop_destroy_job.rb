module ShopifyJobs
  class ShopDestroyJob < ActiveJob::Base

    def perform(shop_id)
      shop = Shop.find(shop_id)
      shop.destroy
        SlackNotifier::CLIENT.ping(
          text: ":rage: Shop destroyed (#{Rails.env}) \n*Store*: #{shop.shopify_domain}\n*Plan*: #{shop.plan.name}\n",
          channel: ENV['SLACK_INSTALLS_CHANNEL']
        )
    end
  end
end
