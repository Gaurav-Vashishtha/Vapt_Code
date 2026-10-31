# frozen_string_literal: true

module ShopifyJobs
  class CustomerCountShopJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 1

    def perform(shop_id)
      return if CustomerSyncControl.killed?

      shop = Shop.find_by(id: shop_id)
      return unless shop

      result = ShopifyServices::CustomerCountFetchService.fetch(shop)
      if result.unauthorized
        CustomerSyncState.mark_unreachable!(shop, 'app uninstalled or token no longer valid')
        return
      end
      return unless result.count.is_a?(Integer)

      shop.update_column(:customer_count, result.count)
      CustomerSyncState.record_count!(shop, result.count)
    end
  end
end
