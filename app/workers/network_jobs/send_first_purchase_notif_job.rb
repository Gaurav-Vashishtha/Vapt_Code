module NetworkJobs
  # NetworkJobs::SendFirstPurchaseNotifJob.perform_async(Shop.last.id,'919130751989')
  class SendFirstPurchaseNotifJob < ApplicationJob
    def perform(shop_id, order_confirmation_id)
      shop = Shop.find(shop_id)
      if (!shop.blank?) && (shop.setting.first_purchase_whatsapp_enabled) && (!shop.setting.first_purchase_discount_off.blank?) && (!shop.setting.first_purchase_discount_code.blank?)
          NetworkServices::WhatsappFirstPurchaseService.call(shop,order_confirmation_id)
      else
        return
      end
    end
  end
end

