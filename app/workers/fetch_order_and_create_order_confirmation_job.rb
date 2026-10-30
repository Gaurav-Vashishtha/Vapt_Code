class FetchOrderAndCreateOrderConfirmationJob < ApplicationJob
  include TwilioHelper
  sidekiq_options queue: 'critical'

  # params = ShopifyServices::OrderGetService.call(
  #   Shop.first,
  #   '5234376540458',
  #   'ahc.com'
  # )
  def perform(order_id, params, shop_id, sync = false)
    shop = Shop.find(shop_id)
    order_params = ShopifyServices::OrderGetService.call(
      shop,
      order_id || params['order_id'],
      params['full_url']
    )
    return unless order_params.is_a?(Hash)
    if order_params.present?
      if order_params['createdAt'].present? && Date.parse(order_params['createdAt']) >= Date.current - 1
        if sync
          OrderConfirmationCreateJob.new.perform(order_params, shop.id)
        else
          OrderConfirmationCreateJob.perform_async(order_params, shop.id)
        end
      else
        puts "Old order received for #{shop_id}"
      end
    end
  end
end





