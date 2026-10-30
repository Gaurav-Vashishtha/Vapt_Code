module ShopifyJobs
  class PartialDiscountCombinesWithSyncJob < ApplicationJob
    queue_as :scheduled_report_delivery

    def perform(shop_id)
      ShopifyServices::PartialDiscountCombinesWithSyncService.call(shop_id)
    end
  end
end
