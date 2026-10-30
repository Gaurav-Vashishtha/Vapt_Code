class AbandonedCartStatusUpdateJob < ApplicationJob

  def perform( shop_id,params)
    shop = Shop.find(shop_id)
    if !params['checkout_id'].blank?
      abandoned_carts = shop.abandoned_carts.where(checkout_id: params['checkout_id'])
      if !abandoned_carts.blank?
        abandoned_carts.first.update(notes:'Recovered')
        OrderMetrics::UpsertService.call(shop, params)
      end
    end
  end
end

