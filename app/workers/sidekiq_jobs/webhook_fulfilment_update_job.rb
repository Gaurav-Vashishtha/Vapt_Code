module SidekiqJobs
    #SidekiqJobs::WebhookFulfilmentUpdateJob.perform_async
  class WebhookFulfilmentUpdateJob < ApplicationJob
    def perform(*args)
      
      count = 0
      success_count = 0
      failed_count = 0
      
      webhook3 = {
        topic: 'orders/fulfilled',
        address: ENV.fetch("AWS_EVENT_BRIDGE_ARN", nil),
        format: 'json'
        }

        Setting.all.each do |setting|
          begin
            shop = setting.shop
            shop.init_session
            webhooks = ShopifyAPI::Webhook.find(:all)
            count = count +1  
            webhooks.each do |webhook|
              puts "Webhook #{webhook.topic}"
              if webhook.topic == 'orders/fulfilled'
                webhook.destroy
                puts 'Order fulfilled webhook destroyed.'
                ShopifyAPI::Webhook.new(webhook3).save 
                success_count = success_count +1 
              end
            end
          rescue Exception => e
            puts "Exception #{e.message}"
            failed_count = failed_count +1
            # SlackNotifyJob.perform_async(
            #   ":rage:  (#{Rails.env})\n  Webhookrefresh job -Exception - #{shop.shopify_domain} #{e.message}"
            # )
          end  
        end
      SlackNotifyJob.perform_async(
        ":heart:  (#{Rails.env})\n  WebhookUpdate job - Shops scanned - #{count} \nWebhooks updated #{success_count} \nFailed Count #{failed_count}"
      )
    end
  end
end