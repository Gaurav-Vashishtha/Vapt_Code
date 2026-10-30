module ShopifyJobs
  class FreeGiftFunctionConfigJob < ApplicationJob
    sidekiq_options queue: :scheduled_report_delivery

    def perform(shop_id)
      FreeGifts::FunctionConfigSync.call(shop_id)
    end
  end
end
