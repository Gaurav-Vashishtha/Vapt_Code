module ShopifyJobs
  # ShopifyJobs::CustomerPullJob.perform_async
  class CustomerPullJob < ApplicationJob
    sidekiq_options queue: 'db_backup', retry: false, concurrency: 1
    def perform
      puts 'Customer Pull job started'
      success = 0
      processed_shops = [] 
      Shop.where(initial_customer_pull_completed:nil, country_code:'INSS').order(id: :desc).each do |shop|
        puts "#{shop.shopify_domain}"
        SlackNotifier::CLIENT.ping(
          text: "CustomerPullJob (#{Rails.env}) - Started Processing #{shop.shopify_domain}",
        )
        ShopifyServices::CustomerPullService.call(shop)
        processed_shops.push(shop.shopify_domain)
        success = success + 1
        if success % 10 ==0
          SlackNotifier::CLIENT.ping(
            text: "CustomerPullJob report (#{Rails.env}) - Processed Shops -  #{processed_shops.join("\n")}",
          )
          processed_shops = []
        end
        if success== 1000
          SlackNotifier::CLIENT.ping(
            text: "CustomerPullJob report (#{Rails.env}) - Processed Shops -  #{processed_shops.join("\n")}",
          )
          return
        end

      end
      SlackNotifier::CLIENT.ping(
            text: "CustomerPullJob report (#{Rails.env}) - Processed Shops - #{processed_shops.join("\n")}",
          )
    end
  end
end
