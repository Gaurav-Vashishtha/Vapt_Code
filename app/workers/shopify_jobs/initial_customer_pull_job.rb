module ShopifyJobs
  class InitialCustomerPullJob < ApplicationJob
    sidekiq_options queue: :global_data_pull,
                    lock: :while_executing,                     # ✅ Allow enqueue, only one execution
                    lock_args_method: ->(_args) { ['global'] }, # ✅ Same lock key = one job at a time
                    retry: 3

    def perform(shop_id)
      return unless LegacyCustomerPull.enabled?

      shop = Shop.find_by(id: shop_id)
      return unless shop
      return if shop.initial_customer_pull_completed.present?

      Rails.logger.info "[InitialCustomerPullJob] Starting for #{shop.shopify_domain}"
      ShopifyServices::CustomerPullService.call(shop)
      shop.update(initial_customer_pull_completed: Time.current)

      SlackNotifier::CLIENT.ping(
        text: "✅ InitialCustomerPullJob completed for #{shop.shopify_domain}"
      )
    rescue => e
      SlackNotifier::CLIENT.ping(
        text: "❌ InitialCustomerPullJob Error for #{shop&.shopify_domain}: #{e.message}"
      )
      raise e
    end
  end
end
