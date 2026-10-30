module ShopifyJobs
  class PrepaidReminderJob < ApplicationJob
   
    # ShopifyJobs::PrepaidReminderJob.perform_async
    
    def perform
      puts 'PrepaidReminderJob started'
      settings = Setting.where('prepaid_enabled', true)
      messages = []
      settings.each do |setting|
        order_confirmations = setting.shop.order_confirmations.
                      where(status:['COD-Verified','COD-Potential-Prepaid']).
                      where('created_at <= ?', Time.now-5.minutes).
                      where('created_at >= ?', Time.now-10.minutes)
                             
        success_count = 0
        error_count = 0
        report_text =''
        shop = setting.shop
        order_confirmations.each_with_index do |order_confirmation,index|
          begin
            resp = NetworkServices::SendPrepaidMessageService.call(shop,order_confirmation)
            success_count = success_count + 1
          rescue Exception => e
              error_count = error_count+1
              messages.push(setting.shop.shopify_domain + ' Error in sending Prepaid Message ' + order_confirmation.order_id )
          end
        end
        if error_count>0
         messages.push("\n#{setting.shop.shopify_domain} \n success count #{success_count} \n Error count  #{error_count}")
        end
      end
      if !messages.blank? && messages.size>0
        message_text = messages.join('\n')
        SlackNotifier::CLIENT.ping(
          text: "PrepaidReminderJob1 report (#{Rails.env}) -  #{message_text}",
        )
      end
      puts 'PrepaidReminderJob1 completed'
    end
  end
end
