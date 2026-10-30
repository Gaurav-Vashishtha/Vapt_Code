# frozen_string_literal: true

module MerchantWhatsapp
  module DigestStats
    module_function

    def for(shop)
      {
        "store.name" => (shop.try(:shop_owner).presence || shop.shopify_domain.to_s.sub(".myshopify.com", "")),
        "owner.name" => shop.try(:owner_name).presence || "there",
        "stats.orders_7d" => orders_last_7d(shop).to_s,
        "stats.period" => "last 7 days"
      }
    end

    def orders_last_7d(shop)
      return 0 unless defined?(OrderConfirmation)

      OrderConfirmation.where(shop_id: shop.id).where("created_at >= ?", 7.days.ago).count
    rescue => e
      Rails.logger.warn("[MerchantWhatsapp::DigestStats] #{e.message}")
      0
    end
  end
end
