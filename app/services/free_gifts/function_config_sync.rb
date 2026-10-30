# frozen_string_literal: true

module FreeGifts
  class FunctionConfigSync
    def self.call(shop_id)
      shop = Shop.find_by(id: shop_id)
      return { ok: false, reason: "shop_not_found" } unless shop

      new(shop).call
    end

    def initialize(shop)
      @shop = shop
    end

    def call
      ensure_discount if FreeGifts.enabled_for?(@shop)
      discount_gid = @shop.setting&.reload&.partial_discount_automatic_app_gid
      return { ok: false, reason: "no_discount" } if discount_gid.blank?

      result = ShopifyServices::MetafieldsSetService.call(@shop, [{
        ownerId: discount_gid,
        namespace: FUNCTION_METAFIELD_NAMESPACE,
        key: FUNCTION_METAFIELD_KEY,
        type: "json",
        value: FreeGifts.function_payload(@shop).to_json
      }])
      errors = Array(result&.dig(:user_errors))
      Rails.logger.warn("[FreeGifts] function config errors shop_id=#{@shop.id} #{errors.inspect}") if errors.any?
      { ok: result.present? && errors.empty?, discount_gid: discount_gid }
    rescue StandardError => e
      Rails.logger.warn("[FreeGifts] function config sync failed shop_id=#{@shop.id} #{e.class}: #{e.message.to_s[0, 200]}")
      { ok: false, reason: "exception", error: e.message }
    end

    private

    def ensure_discount
      ShopifyServices::PartialDiscountAutomaticAppEnsureService.call(@shop.id, sync_free_gifts: false)
    end
  end
end
