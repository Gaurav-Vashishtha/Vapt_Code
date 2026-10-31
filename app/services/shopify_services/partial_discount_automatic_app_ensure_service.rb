module ShopifyServices
  class PartialDiscountAutomaticAppEnsureService
    def self.call(shop_id, sync_free_gifts: true)
      shop = Shop.find_by(id: shop_id)
      return { ok: false, skipped: true, reason: "shop_not_found" } unless shop

      new(shop, sync_free_gifts: sync_free_gifts).call
    end

    def initialize(shop, sync_free_gifts: true)
      @shop = shop
      @setting = shop.setting
      @sync_free_gifts = sync_free_gifts
    end

    def call
      return { ok: false, skipped: true, reason: "setting_not_found" } unless @setting

      Rails.logger.info("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} starting")

      discount_function_id = ENV.fetch("PARTIAL_PAYMENT_DISCOUNT_FUNCTION_ID", nil).to_s.strip
      if discount_function_id.blank?
        Rails.logger.warn("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} missing PARTIAL_PAYMENT_DISCOUNT_FUNCTION_ID")
        return { ok: false, skipped: true, reason: "missing_discount_function_id" }
      end

      if @setting.partial_discount_automatic_app_gid.present?
        case discount_state_in_shopify(discount_gid: @setting.partial_discount_automatic_app_gid)
        when :present
          Rails.logger.info("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} discount exists gid=#{@setting.partial_discount_automatic_app_gid}")
          return { ok: true, skipped: true, reason: "already_exists" }
        when :unknown
          Rails.logger.warn("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} could not verify discount gid=#{@setting.partial_discount_automatic_app_gid}, leaving it untouched")
          return { ok: false, skipped: true, reason: "verification_failed" }
        end

        Rails.logger.warn("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} discount missing in Shopify, clearing gid=#{@setting.partial_discount_automatic_app_gid}")
        @setting.update!(partial_discount_automatic_app_gid: nil)
      end

      create_discount!(discount_function_id: discount_function_id)
    rescue => e
      Rails.logger.error("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} failed #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace.present?
      { ok: false, skipped: false, reason: "exception", error: e.message }
    end

    private

    def create_discount!(discount_function_id:)
      @shop.init_session
      client = ShopifyAPI::GraphQL.client

      timestamp = Time.current.to_i
      unique_title = "Partial Payment Discount #{timestamp}"

      service = ShopifyServices::DiscountAutomaticAppCreateService.new(
        client,
        @shop,
        title: unique_title,
        function_id: discount_function_id,
        discount_classes: ["ORDER", "PRODUCT"],
        combines_with: @setting.partial_discount_combines_with_input,
        starts_at: nil
      )

      response_data = service.create_automatic_app_discount.to_h

      if response_data["errors"]&.any?
        error_msg = response_data["errors"].map { |e| e["message"] }.join(", ")
        Rails.logger.error("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} GraphQL errors: #{error_msg}")
        return { ok: false, skipped: false, reason: "graphql_errors", error: error_msg }
      end

      user_errors = response_data.dig("data", "discountAutomaticAppCreate", "userErrors")
      if user_errors&.any?
        error_msg = user_errors.map { |e| e["message"] }.join(", ")
        Rails.logger.error("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} user errors: #{error_msg}")
        return { ok: false, skipped: false, reason: "user_errors", error: error_msg }
      end

      discount = response_data.dig("data", "discountAutomaticAppCreate", "automaticAppDiscount")
      discount_id = discount&.dig("discountId")
      if discount_id.blank?
        Rails.logger.warn("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} created discount but missing discountId in response")
        return { ok: false, skipped: false, reason: "missing_discount_id" }
      end

      @setting.update!(partial_discount_automatic_app_gid: discount_id)
      Rails.logger.info("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} stored discount gid=#{discount_id}")
      ShopifyJobs::FreeGiftFunctionConfigJob.perform_async(@shop.id) if @sync_free_gifts && FreeGifts.enabled_for?(@shop)
      { ok: true, skipped: false, reason: "created", discount_gid: discount_id }
    end

    # :present | :absent | :unknown — :unknown means Shopify could not be
    # reached, which must never be treated as :absent or a transient outage
    # recreates a discount that already exists.
    def discount_state_in_shopify(discount_gid:)
      return :absent if discount_gid.blank?

      @shop.init_session
      client = ShopifyAPI::GraphQL.client

      query = client.parse <<-'GRAPHQL'
        query($id: ID!) {
          discountNode(id: $id) {
            id
            discount {
              ... on DiscountAutomaticApp {
                discountId
                title
                status
                endsAt
                appDiscountType {
                  functionId
                }
              }
            }
          }
        }
      GRAPHQL

      response = client.query(query, variables: { id: discount_gid }).to_h

      if response["errors"]&.any?
        error_msg = response["errors"].map { |e| e["message"] }.join(", ")
        Rails.logger.warn("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} discount check errors: #{error_msg}")
        return :unknown
      end

      discount = response.dig("data", "discountNode", "discount")
      return :absent unless discount.present?

      discount["status"] == "EXPIRED" ? :absent : :present
    rescue => e
      Rails.logger.warn("[PartialDiscountAutomaticAppEnsureService] shop=#{@shop.shopify_domain} discount check failed #{e.class}: #{e.message}")
      :unknown
    end
  end
end

