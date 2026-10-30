module SidekiqJobs
  class UninstalledShopsCleanupJob < ApplicationJob
    def  perform(*args)
        count = 0
        success_count = 0
        Shop.all.each do |shop| 
          begin
            count = count + 1
            shop.init_session
            ShopifyAPI::Shop.current
          rescue Exception => e
            if e.message.include? 'Unauthorized ([API] Invalid API key'
              puts "Uninstalled Shop #{shop.shopify_domain}"
              UninstallNewJob.perform_async(shop.shopify_domain,'')
              success_count = success_count + 1
            end
          end
          if count % 100 == 0
            SlackNotifyJob.perform_async(
              ":heart:  (#{Rails.env})\n  Completion of Uninstalled cleanup - Shops scanned - #{count} \Shops destroyed #{success_count}"
            )
          end 
        end
      end
    end
  end