module SidekiqJobs
  class IncorrectSetupJob < ApplicationJob
    def perform(*args)
      total_shops = 0
      incorrect_shops = 0
      failed_shops = 0
      incorrect_domains = []

      Setting.where(enable_pre_order_otp: true).each do |setting|
        shop = setting.shop
        total_shops += 1

        begin
          resp = ShopifyServices::ShopifyAssetService.new(shop).is_cod_king_block_enabled?
          unless resp
            incorrect_shops += 1
            incorrect_domains << shop.shopify_domain
          end
        rescue => e
          failed_shops += 1
          Rails.logger.error("Error checking block for #{shop.shopify_domain}: #{e.message}")
        end
      end

      message = <<~SLACK
        :warning: *Incorrect Setup Job Summary* (#{Rails.env})
        • Total Shops Scanned: *#{total_shops}*
        • Shops with Incorrect Setup: *#{incorrect_shops}*
        • Errors/Failures: *#{failed_shops}*

        #{incorrect_shops > 0 ? "*Incorrect Shops:* \n" + incorrect_domains.join("\n") : "All shops are correctly set up."}
      SLACK

      SlackNotifyJob.perform_async(message)
    end
  end
end
