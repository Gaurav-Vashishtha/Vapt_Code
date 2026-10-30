module ShopifyJobs
  class PartialDiscountAutomaticAppJob < ApplicationJob
    queue_as :scheduled_report_delivery

    def perform(shop_id)
      ShopifyServices::PartialDiscountAutomaticAppEnsureService.call(shop_id)
    end
  end
end

