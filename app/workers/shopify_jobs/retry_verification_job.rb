module ShopifyJobs
  class RetryVerificationJob < ApplicationJob
    
    LOOK_BACK_DAYS = 1
    
    def perform
      puts 'Retry job started'
      settings = Setting.where('retry > ?', -1)
      .where(Setting.arel_table[:sms].eq(true)
      .or(Setting.arel_table[:send_verification_link_only].eq(true)))
      
      messages = []
      settings.each do |setting|
        order_confirmations = setting.shop.order_confirmations.
                      where(status: ['Pending', 'COD-Potential-Prepaid']).
                      where.not(is_retried:true).
                      where('created_at < ?', Time.now-setting.retry.minutes).
                      where('created_at > ?', Time.now-LOOK_BACK_DAYS.days)
        setting.shop.init_session
        success_count = 0
        error_count = 0
        report_text =''
        order_confirmations.each_with_index do |order_confirmation,index|
        begin
          if order_confirmation.status == 'COD-Potential-Prepaid' && setting.send_verification_link_only == false
            next  
          end
          order = ShopifyAPI::Order.find(order_confirmation.order_id)
          if !order.blank? 
            if ((ENV.fetch("WHATSAPP_COUNTRIES", nil).split(",").include?order_confirmation.country_code) && (setting.whatsapp_enabled==true))
              NetworkServices::WhatsappRetryService.call(setting.shop,order_confirmation)
            else  
              NetworkServices::SendSmsService.call(order_confirmation.id, setting.retry_template, '',true)
            end
            order_confirmation.update(is_retried:true)
            success_count= success_count+1
          else
            error_count = error_count+1
            messages.push(setting.shop.shopify_domain + ' Error in retrying order ' + order_confirmation.order_id)
          end
        rescue Exception => e
            error_count = error_count+1
            messages.push(setting.shop.shopify_domain + ' Error in retrying order ' + order_confirmation.id.to_s)
            order_confirmation.update(status:'RETRY-FAILED')
        end
        end
        if error_count>0 || success_count > 1
         messages.push("\n#{setting.shop.shopify_domain} \n success count #{success_count} \n Error count  #{error_count}")
        end
      end
      if !messages.blank? && messages.size>0
        message_text = messages.join('\n')
        SlackNotifier::CLIENT.ping(
          text: "Retry order job report (#{Rails.env}) -  #{message_text}",
        )
      end
      puts 'Retry job completed'
    end
  end
end
