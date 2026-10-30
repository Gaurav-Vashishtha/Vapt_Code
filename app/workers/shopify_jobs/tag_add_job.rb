module ShopifyJobs
  class TagAddJob < ApplicationJob
    def perform(order_confirmation_id, tag = '')
      @order_confirmation = OrderConfirmation.find(order_confirmation_id)
      @shop = @order_confirmation.shop
      if @shop.setting.sms
        ShopifyServices::OrderTagsAddService.call(
          @shop, @order_confirmation.order_id, tag
        )
      end
    end
  end
end