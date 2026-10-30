module ShopifyJobs
  class CodPrepaidJob < ApplicationJob

    # ShopifyJobs::CodPrepaidJob.perform_async
    
    LOOK_BACK_DAYS = 2
    
    def perform
      puts 'CodPrepaidlJob job started'
      scanned_orders = 0 
      failed_orders = 0 
      success_orders = 0 
      order_confirmations =  OrderConfirmation.where.not(payment_link_id: nil).
                              where('created_at > ?', Time.now-LOOK_BACK_DAYS.days).
                              where.not(status:'COD-Prepaid')
                              
      order_confirmations.each  do |order_confirmation|
        begin
          scanned_orders = scanned_orders + 1
          Razorpay.setup(order_confirmation.shop.setting.payment_provider_api_key, order_confirmation.shop.setting.payment_provider_api_secret)
          Razorpay.headers = {"Content-type" => "application/json"}
          resp = Razorpay::PaymentLink.fetch(order_confirmation.payment_link_id)
          
          if !resp.blank? && resp.status=='paid'
            prepaid_resp = ShopifyServices::PrepaidOrderService.call(order_confirmation.shop, order_confirmation.id)
            if !prepaid_resp.blank?
              success_orders = success_orders+1
            end
          end
        rescue Exception => e
          SlackNotifier::CLIENT.ping(
            text: "Error processing COD to prepaid (#{Rails.env}) - #{order_confirmation.id} - #{order_confirmation.shop.shopify_domain} #{e} Resp from Razorpay #{resp} #payment Link#{order_confirmation.prepaid_link}",
          )
          failed_orders = failed_orders+1
        end
      end
      
      SlackNotifier::CLIENT.ping(
        text: "Report for COD-Prepaid Job (#{Rails.env}) - Scanned Orders #{scanned_orders} - Success Orders #{success_orders} Failed Orders #{failed_orders} ",
      )
      puts 'CodPrepaidlJob job completed'
    end
  end
end
