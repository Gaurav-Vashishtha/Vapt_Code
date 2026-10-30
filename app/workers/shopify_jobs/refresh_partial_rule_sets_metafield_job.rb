# frozen_string_literal: true

module ShopifyJobs
  class RefreshPartialRuleSetsMetafieldJob < ActiveJob::Base
    queue_as :default

    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      return unless shop

      shop.sync_partial_rule_sets_metafields
    end
  end
end
