module NetworkJobs
  # NetworkJobs::FirstPurchaseScheduleJob.perform_async(Shop.last.id,OrderConfirmation.last.id)
  class FirstPurchaseScheduleJob < ApplicationJob
    def perform(shop_id, order_confirmation_id)
      shop = Shop.find(shop_id)
      if shop.setting.locked 
        return
      end
      if (!shop.blank?) && shop.setting.first_purchase_whatsapp_enabled
        order_confirmation = OrderConfirmation.find(order_confirmation_id)
        params = ShopifyServices::OrderFullGetService.call(
            shop,
            order_confirmation.order_id
          )
          numberOfOrders = params.dig('customer','numberOfOrders') && params.dig('customer','numberOfOrders').to_i 
          if numberOfOrders <= 1
            # Schedule it according to configuration.
            if !shop.setting.first_purchase_schedule.blank?
              shop.setting.first_purchase_schedule.split(",").each do|schedule|
                mins = schedule.to_i                
                  NetworkJobs::SendFirstPurchaseNotifJob.perform_in( mins*(1.minutes), shop.id,order_confirmation.id)
              end
            else
              NetworkJobs::SendFirstPurchaseNotifJob.perform_async(shop.id,order_confirmation.id)
            end
          end
      else
        return
      end
    end
  end
end

