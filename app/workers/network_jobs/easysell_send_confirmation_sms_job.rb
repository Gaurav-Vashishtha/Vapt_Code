
#NetworkJobs::EasysellSendConfirmationSmsJob.perform_async('919130751989','Test Store','IN','D123','example.com')
module NetworkJobs
  class EasysellSendConfirmationSmsJob < ApplicationJob
    def perform(phone, store, country_code,order_number,order_url)
      shop = Shop.find_by(shopify_domain:'easysell5.myshopify.com')
      NetworkServices::EasysellSendConfirmationSmsService.call(10326295, phone,store,country_code,order_number,order_url)
      #NetworkServices::EasysellSendConfirmationSmsService.call(OrderConfirmation.last.id, '+919130751989','TestStore','IN','#D123','example.com')
      
    end
  end
end
