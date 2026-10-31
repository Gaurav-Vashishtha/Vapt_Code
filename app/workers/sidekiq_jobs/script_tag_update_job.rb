module SidekiqJobs
  class ScriptTagUpdateJob < ApplicationJob
    def perform(*args)
      success = 0
      failed = 0
      failed_shops = []
      Shop.all.each do |shop|
        begin
          if shop.setting.sms!=true
            puts "Not enabled skipping #{shop.shopify_domain}}"
            next
          end
          shop.init_session
          st = ShopifyAPI::ScriptTag.first
          if !st.blank?
            st.src="https://codkingscript.s3.us-west-2.amazonaws.com/script.js"
            if st.save
              success = success +1
              puts "Success : #{shop.shopify_domain}"
            else
              failed = failed +1
              failed_shops.push(shop.shopify_domain)
            end
          else
                scripttag = {
                event: 'onload',
                display_scope: 'order_status',
                cache: Rails.env.production?,
                src:   "https://#{ENV.fetch("APP_HOST", nil)}/script.js" 
              }
              st = ShopifyAPI::ScriptTag.new(scripttag)
              if st.save
                success = success + 1
              else
                failed = failed + 1
                failed_shops.push(shop.shopify_domain)
              end
          end
        rescue Exception => e
          puts "Exception #{e.message}"
        end 
      end
      SlackNotifier::CLIENT.ping(
        text: ":sunglasses: *Script Tag Shops* (#{Rails.env}) \n Success #{success} failed shops #{failed} #{failed_shops} ",
      )
    end
  end
end