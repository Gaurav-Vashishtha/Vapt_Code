module SidekiqJobs
  class OrderWebhookRemoveJob < ApplicationJob
    def perform
      webhook_removed = []
      count = 0
      
      Setting.where("(sms IS NULL OR sms != ?) AND (enable_pre_order_otp IS NULL OR enable_pre_order_otp != ?) AND (prepaid_enabled IS NULL OR prepaid_enabled != ?) AND (cod_fee_enabled IS NULL OR cod_fee_enabled != ?) AND (enable_shipping_cod_fees IS NULL OR enable_shipping_cod_fees != ?) AND (confirmation_sms_enabled IS NULL OR confirmation_sms_enabled != ?) AND (confirmation_whatsapp IS NULL OR confirmation_whatsapp != ?) AND (enable_fulfilment_message IS NULL OR enable_fulfilment_message != ?) AND (fulfilment_whatsapp IS NULL OR fulfilment_whatsapp != ?) AND (abandoned_cart_enabled IS NULL OR abandoned_cart_enabled != ?) AND (ac_whatsapp IS NULL OR ac_whatsapp != ?)", true, true, true, true, true, true, true, true, true, true, true).order(id: :desc).each do |setting|
        shop=setting.shop
        begin
          shop.init_session
          webhooks = ShopifyAPI::Webhook.find(:all)
          
          webhooks.each do |webhook|
            puts "Webhook #{webhook.topic}"
            if webhook.topic == 'orders/fulfilled'
              webhook.destroy
              puts "fulfilment webhook destroyed. #{shop.shopify_domain} - #{shop.id}"
            end
            if webhook.topic == 'orders/create'
              webhook.destroy
              puts "Order webhook destroyed. #{shop.shopify_domain} - #{shop.id}"
            end
          end
          count = count +1 
          webhook_removed.push(shop.shopify_domain)
          webhook1 =  {
            topic: 'app/uninstalled',
            address: "https://#{ENV.fetch("APP_HOST", nil)}/webhooks/uninstall",
            format: 'json'
          }
       
          ShopifyAPI::Webhook.new(webhook1).save  
       rescue Exception => e
         #puts "Exception #{e.message}"
        end
      end
      puts "Total #{count} webhook_removed #{webhook_removed}"
      SlackNotifyJob.perform_async(
        ":heart:  (#{Rails.env})\n Total #{count} webhook_removed #{webhook_removed}"
      )
    end
  end
end