# frozen_string_literal: true

module CodForm
  # Daily: refreshes the product list of every active pre-purchase upsell rule
  # (CodForm::PreUpsellCatalog), so collection rules follow the collection and products that
  # were archived or sold out for good drop out.
  class PreUpsellRefreshJob < ApplicationJob
    sidekiq_options queue: "low", retry: 1

    def perform
      refreshed = 0
      CodForm::Offer.where(offer_type: CodForm::PreUpsellCatalog::TYPES, status: CodForm::Offer::STATUS_ACTIVE)
                    .includes(:shop).find_each do |offer|
        next if offer.shop.nil?

        refreshed += 1 if CodForm::PreUpsellCatalog.refresh!(offer)
      end
      Rails.logger.info("[CodForm::PreUpsellRefreshJob] refreshed=#{refreshed}")
    end
  end
end
