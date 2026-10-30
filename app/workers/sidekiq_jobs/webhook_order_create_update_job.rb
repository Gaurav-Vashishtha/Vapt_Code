module SidekiqJobs
  class WebhookOrderCreateUpdateJob < ApplicationJob
   #SidekiqJobs::WebhookOrderCreateUpdateJob.perform_async

   def perform(*args)
    count = 0
    success_count = 0
    failed_count = 0
  
    Setting.all.order(id: :asc).each do |setting|
      begin
        shop = setting.shop
        shop.init_session
        webhooks = ShopifyAPI::Webhook.find(:all)
        count += 1
        puts "Count #{count} shop #{shop.shopify_domain}"
        if webhooks.count > 0
          webhooks.each do |webhook|
            puts "Webhook #{webhook.topic}"
            if webhook.topic == 'orders/create' && webhook.address != ENV['AWS_ORDER_CREATE_EVENT_BRIDGE_ARN']
              webhook.address = ENV['AWS_ORDER_CREATE_EVENT_BRIDGE_ARN']
              webhook.save
              success_count += 1
              puts "Order create updated successfully - #{success_count} - #{count}"
            elsif webhook.topic != 'orders/create' && webhook.address != ENV['AWS_EVENT_BRIDGE_ARN']
              webhook.address = ENV['AWS_EVENT_BRIDGE_ARN']
              webhook.save
              success_count += 1
              puts "#{webhook.topic} updated successfully - #{success_count} - #{count}"
            end
          end
        end
      rescue Exception => e
        puts "Exception #{e.message}"
        failed_count += 1
      end
    end
  
    SlackNotifyJob.perform_async(
      ":heart:  (#{Rails.env})\n  WebhookUpdate job - Shops scanned - #{count} \nWebhooks updated #{success_count} \nFailed Count #{failed_count}"
    )
    end

  end
end