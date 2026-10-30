module ShopifyServices
  # Pushes the merchant's discount-combination choice onto the existing
  # partial-payment app discount. Only ever runs off an explicit settings save
  # — never from the ensure cron — so a shop that has not touched the setting
  # keeps whatever combinations its discount was created with.
  class PartialDiscountCombinesWithSyncService
    def self.call(shop_id)
      shop = Shop.find_by(id: shop_id)
      return { ok: false, skipped: true, reason: "shop_not_found" } unless shop

      new(shop).call
    end

    def initialize(shop)
      @shop = shop
      @setting = shop.setting
    end

    def call
      return { ok: false, skipped: true, reason: "setting_not_found" } unless @setting

      discount_gid = @setting.partial_discount_automatic_app_gid
      if discount_gid.blank?
        # No discount yet — the ensure service will create one with these values.
        Rails.logger.info("[PartialDiscountCombinesWithSyncService] shop=#{@shop.shopify_domain} no discount gid, nothing to sync")
        return { ok: true, skipped: true, reason: "no_discount_gid" }
      end

      combines_with = @setting.partial_discount_combines_with
      Rails.logger.info("[PartialDiscountCombinesWithSyncService] shop=#{@shop.shopify_domain} syncing #{combines_with.inspect} gid=#{discount_gid}")

      @shop.init_session
      client = ShopifyAPI::GraphQL.client

      response_data = ShopifyServices::DiscountAutomaticAppUpdateService.new(
        client,
        @shop,
        discount_gid: discount_gid,
        combines_with: combines_with
      ).update_automatic_app_discount.to_h

      if response_data["errors"]&.any?
        error_msg = response_data["errors"].map { |e| e["message"] }.join(", ")
        Rails.logger.error("[PartialDiscountCombinesWithSyncService] shop=#{@shop.shopify_domain} GraphQL errors: #{error_msg}")
        return { ok: false, skipped: false, reason: "graphql_errors", error: error_msg }
      end

      user_errors = response_data.dig("data", "discountAutomaticAppUpdate", "userErrors")
      if user_errors&.any?
        error_msg = user_errors.map { |e| e["message"] }.join(", ")
        Rails.logger.error("[PartialDiscountCombinesWithSyncService] shop=#{@shop.shopify_domain} user errors: #{error_msg}")
        return { ok: false, skipped: false, reason: "user_errors", error: error_msg }
      end

      Rails.logger.info("[PartialDiscountCombinesWithSyncService] shop=#{@shop.shopify_domain} synced gid=#{discount_gid}")
      { ok: true, skipped: false, reason: "synced", combines_with: combines_with }
    rescue => e
      Rails.logger.error("[PartialDiscountCombinesWithSyncService] shop=#{@shop.shopify_domain} failed #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace.present?
      { ok: false, skipped: false, reason: "exception", error: e.message }
    end
  end
end
