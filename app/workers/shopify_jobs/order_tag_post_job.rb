module ShopifyJobs
  class OrderTagPostJob < ApplicationJob
 
    def perform(shop_id, shopify_order_id, tag = '')
      shop = Shop.find(shop_id)
      resolved_tag = tag.presence ||
                     shop.setting&.verification_tag.presence ||
                     ShopifyJobs::OrderPostJob::DEFAULT_VERIFICATION_TAG

      return if resolved_tag.blank?

      ShopifyServices::OrderTagPostService.call(shop, shopify_order_id, resolved_tag)
    end
  end
end