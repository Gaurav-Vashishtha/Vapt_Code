module SidekiqJobs
  class WebhookRemoveJob < ApplicationJob
    def perform(*args)
      
      count = 0
      success_count = 0
      failed_count = 0
      
      webhook1 =  {
            topic: 'app/uninstalled',
            address: ENV.fetch("AWS_EVENT_BRIDGE_ARN", nil),
            format: 'json'
          }
      webhook2 = {
            topic: 'orders/create',
            address: ENV.fetch("AWS_ORDER_CREATE_EVENT_BRIDGE_ARN", nil),
            format: 'json'
          }
      
          webhook3 = {
            topic: 'orders/fulfilled',
            address: ENV.fetch("AWS_EVENT_BRIDGE_ARN", nil),
            format: 'json'
            }

            webhook4 = {
            topic: 'customers/create',
            address: ENV.fetch("AWS_EVENT_BRIDGE_ARN", nil),
          format: 'json'
            }

        Shop.where("updated_at > ? AND updated_at <= ?", 600.days.ago, 120.days.ago).each do |shop|
        begin
          shop.init_session
          setting = shop.setting
          webhooks = ShopifyAPI::Webhook.find(:all)
          count = count +1
          puts "Processed #{count}"
          webhook_response = ShopifyAPI::Webhook.new(webhook2).save 
          webhook_response_2 = ShopifyAPI::Webhook.new(webhook3).save 

          puts "#{shop.shopify_domain} - #{webhook_response}"

          if webhook_response || webhook_response_2
            success_count = success_count +1 
          else
            failed_count = failed_count + 1
          end

          # if (setting.first_purchase_whatsapp_enabled==true ||  setting.sms==true || setting.enable_pre_order_otp==true || setting.prepaid_enabled==true  || setting.cod_fee_enabled==true || setting.enable_shipping_cod_fees== true || setting.confirmation_sms_enabled== true ||  setting.confirmation_whatsapp==true || setting.abandoned_cart_enabled==true ||  setting.ac_whatsapp==true || setting.enable_fulfilment_message==true || setting.fulfilment_whatsapp==true)
          #   ShopifyAPI::Webhook.new(webhook2).save 
          # end
          # else
          #   webhooks.each do |webhook|
          #     puts "Webhook #{webhook.topic}"
          #     if webhook.topic == 'orders/create'
          #       webhook.destroy
          #       puts "Order Create webhook destroyed. #{shop.shopify_domain}"
          #       success_count = success_count +1 
          #     end
          #   end
          # end

          # if (setting.first_purchase_whatsapp_enabled==true)
          #   ShopifyAPI::Webhook.new(webhoo4).save 
          # else
          #   webhooks.each do |webhook|
          #     if webhook.topic == 'customers/create'
          #       webhook.destroy
          #       puts "Customer Create webhook destroyed. #{shop.shopify_domain}"
          #       success_count = success_count +1 
          #     end
          #   end
          # end

          # if (setting.enable_fulfilment_message && setting.enable_fulfilment_message==true) || (setting.fulfilment_whatsapp && setting.fulfilment_whatsapp==true)
          #   ShopifyAPI::Webhook.new(webhook3).save 
          # else
          #   webhooks.each do |webhook|
          #     if webhook.topic == 'orders/fulfilled'
          #       webhook.destroy
          #       puts "Order fulfilled webhook destroyed. #{shop.shopify_domain}"
          #       success_count = success_count +1 
          #     end
          #   end
          # end
           
        rescue Exception => e
          puts "Exception #{e.message}"
          failed_count = failed_count +1
          # SlackNotifyJob.perform_async(
          #   ":rage:  (#{Rails.env})\n  Webhookrefresh job -Exception - #{shop.shopify_domain} #{e.message}"
          # )
        end 
      end 
      SlackNotifyJob.perform_async(
        ":heart:  (#{Rails.env})\n  Webhookrefresh job - Shops scanned - #{count} \nWebhooks created #{success_count} \nFailed Count #{failed_count}"
      )
    end
  end
end