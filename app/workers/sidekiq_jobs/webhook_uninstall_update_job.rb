module SidekiqJobs
  class WebhookUninstallUpdateJob < ApplicationJob
    def perform(*args)
      
      count = 0
      success_count = 0
      failed_count = 0
      
      webhook3 = {
        topic: 'app/uninstalled',
        address: ENV['AWS_EVENT_BRIDGE_ARN'],
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
            if webhook.topic == 'app/uninstalled' && (webhook.address.include? 'glacial')
              webhook.destroy
              puts 'App Uninstalled webhook destroyed.'
              
              ShopifyAPI::Webhook.new(webhook3).save  
              success_count = success_count +1 
              puts "Shop found and succeeded #{shop.shopify_domain}"
            end
          end
        rescue Exception => e
          puts "Exception #{e.message}"
          failed_count = failed_count +1
        end 
      end 
      SlackNotifyJob.perform_async(
        ":heart:  (#{Rails.env})\n  WebhookUpdate job - Shops scanned - #{count} \nWebhooks updated #{success_count} \nFailed Count #{failed_count}"
      )
    end
  end
end