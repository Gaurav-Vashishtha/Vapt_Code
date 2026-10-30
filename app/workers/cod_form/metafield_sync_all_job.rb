# frozen_string_literal: true

module CodForm
  # Rewrites the `codk.cod_form` metafield of every shop that has one (A.3: after the global kill
  # switch is flipped, every shop's metafield must say `enabled: false`; also used after a
  # feature-gate or module-default change in the internal admin).
  #
  #   CodForm::MetafieldSyncAllJob.perform_async
  class MetafieldSyncAllJob < ApplicationJob
    sidekiq_options queue: :low, retry: 1

    BATCH = 500
    SPREAD_SECONDS = 2 # per batch, so thousands of shops do not hit Shopify at once

    def perform
      batch_index = 0
      CodForm::ShopConfig
        .where("storefront_mode = ? OR metafield_synced_at IS NOT NULL", CodForm::ShopConfig::STOREFRONT_MODE_COD_FORM)
        .in_batches(of: BATCH) do |batch|
          batch.pluck(:shop_id).each do |shop_id|
            CodForm::MetafieldSyncJob.perform_in(batch_index * SPREAD_SECONDS, shop_id, true, true)
          end
          batch_index += 1
        end
    end
  end
end
