
#NetworkJobs::EasysellSendAcSmsJob.perform_async('919130751989','Test Store','IN','example.com')
module NetworkJobs
  class EasysellSendAcSmsJob < ApplicationJob
    def perform(phone, store, country_code,url)
      shop = Shop.find_by(shopify_domain:'easysell5.myshopify.com')
      NetworkServices::EasysellSendAcSmsService.call(10326295,store,url,phone,country_code)
      
    end
  end
end
