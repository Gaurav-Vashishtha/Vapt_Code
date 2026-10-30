module SidekiqJobs
  class ScriptTagRemoveJob < ApplicationJob
    def perform(*args)
      
      count = 0
      success_count = 0
      failed_count = 0
    
      Shop.all.each do |shop|
        begin
          shop.init_session
          setting = shop.setting
          webhooks = ShopifyAPI::ScriptTag.all
          count = count +1
          if !(setting.sms==true || setting.enable_pre_order_otp==true || setting.prepaid_enabled==true  || setting.cod_fee_enabled==true || setting.enable_shipping_cod_fees== true || setting.confirmation_sms_enabled== true ||  setting.confirmation_whatsapp==true || setting.abandoned_cart_enabled==true ||  setting.ac_whatsapp==true || setting.enable_fulfilment_message==true || setting.fulfilment_whatsapp==true)
            puts "Remove script tag : #{shop.shopify_domain}" 
            success_count = success_count + 1
          end 
        rescue Exception => e
          puts "Exception #{e.message}"
          failed_count = failed_count +1
          # SlackNotifyJob.perform_async(
          #   ":rage:  (#{Rails.env})\n  Webhookrefresh job -Exception - #{shop.shopify_domain} #{e.message}"
          # )
        end 
      end #loop ends
      SlackNotifyJob.perform_async(
        ":heart:  (#{Rails.env})\n  ScriptTagRemoveJob job - Shops scanned - #{count} \nWebhooks destroyed #{success_count} \nFailed Count #{failed_count}"
      )
    end 
  end
end