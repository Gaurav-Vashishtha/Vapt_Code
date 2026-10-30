
#NetworkJobs::EasysellSendSmsJob.perform_async('919130751989','Testing','IN','1234')
module NetworkJobs
  class EasysellSendSmsJob < ApplicationJob
    def perform(phone, store, country_code,otp)
      shop = Shop.find_by(shopify_domain:'easysell5.myshopify.com')
      order_confirmation_id = 10326295
      
      NetworkServices::EasysellSendSmsService.call(order_confirmation_id, shop.setting.retry_template, '',false, phone, store, country_code,otp)
    end
  end
end
