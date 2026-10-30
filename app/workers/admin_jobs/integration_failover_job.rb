module AdminJobs
  class IntegrationFailoverJob < ApplicationJob
    sidekiq_options queue: 'administration'

    def perform

      # if less than 60% verified orders in last 15 minutes
      time_frame = 15.minutes.ago
      switch_below_pct = 60

      Shop.includes(:integrations).uniq.each do |shop|
        verified_orders = shop.order_confirmations.since(time_frame).verified.size
        pending_orders = shop.order_confirmations.since(time_frame).pending.size
        total_cod_orders = verified_orders + pending_orders

        if total_cod_orders > 0
          verified_pct = (100 * verified_orders) / total_cod_orders
          pending_pct = (100 * pending_orders) / total_cod_orders
          if verified_pct < switch_below_pct
            # switch provider
            fallback = shop.integrations.where(active: false).first
            if fallback && shop.setting.update(
              provider: fallback.provider,
              provider_api_key: fallback.provider_api_key,
              provider_sender_id: fallback.provider_sender_id
            )
              # mark all integrations inactive
              shop.integrations.update(active: false)
              # mark fallback as active
              fallback.update(active: true)
              SlackNotifyJob.perform_async(
                ":sunglasses: (#{Rails.env})\n Switched provider to `#{shop.setting.provider}` for #{shop.shopify_domain}\nVerified: *#{verified_pct} %*   (#{verified_orders}) \nPending: *#{pending_pct}%*  (#{pending_orders})"
              )
            end
          end
        end
      end
    end

  end
end