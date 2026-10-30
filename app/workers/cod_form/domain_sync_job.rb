# frozen_string_literal: true

module CodForm
  # Refreshes cod_form_shop_configs.allowed_origins from the shop's Shopify domains (B.1).
  # Enqueued when COD Form mode is turned on and by `POST /cod_form/setup/refresh_embed`.
  #
  #   CodForm::DomainSyncJob.perform_async(shop_id)
  class DomainSyncJob < ApplicationJob
    sidekiq_options queue: :low, retry: 2

    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      return if shop.nil?

      CodForm::DomainSyncService.call(shop)
    end
  end
end
