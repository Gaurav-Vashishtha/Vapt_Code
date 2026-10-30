module ShopifyServices
  class OrderShippingStatusSyncService < ApplicationService
    TERMINAL_SHIPPING_STATUSES = %w[delivered undelivered].freeze
    RATE_LIMIT_MAX_RETRIES = 30 # 1s sleep each; ~30s backoff per order before giving up

    def initialize(shop, days = 7)
      @shop = shop
      @days = days.to_i
      @days = 7 if @days <= 0
    end

    def call
      return { updated: 0, scanned: 0 } if @shop.blank?

      from_time = @days.days.ago.beginning_of_day
      to_time = Time.current.end_of_day

      sync_scope = OrderConfirmation
        .where(shop_id: @shop.id, created_at: from_time..to_time)
        .where(
          "shipping_status IS NULL OR shipping_status = '' OR LOWER(shipping_status) NOT IN (?)",
          TERMINAL_SHIPPING_STATUSES
        )
        .where.not(order_id: [nil, ""])

      order_ids_to_sync = sync_scope.distinct.pluck(:order_id).map(&:to_s)
      return touch_shop_and_result(0, 0) if order_ids_to_sync.blank?

      @shop.init_session
      updated_count = 0

      order_ids_to_sync.each do |order_id|
        order = find_order_with_rate_limit_backoff(order_id)
        next if order.blank?

        shipping_status = shipping_status_from_order(order)
        next if shipping_status.blank?

        updated = OrderConfirmation
          .where(shop_id: @shop.id, order_id: order_id)
          .where(
            "shipping_status IS NULL OR shipping_status = '' OR LOWER(shipping_status) NOT IN (?)",
            TERMINAL_SHIPPING_STATUSES
          )
          .update_all(shipping_status: shipping_status, updated_at: Time.current)

        updated_count += updated
      rescue => e
        Rails.logger.warn("[OrderShippingStatusSyncService] shop_id=#{@shop.id} order_id=#{order_id} error=#{e.class}: #{e.message}")
      end

      touch_shop_and_result(updated_count, order_ids_to_sync.size)
    end

    private

    # Shopify REST bucket ~2 req/s per shop; on 429 sleep 1s and retry.
    def find_order_with_rate_limit_backoff(order_id)
      attempts = 0
      loop do
        return ShopifyAPI::Order.find(order_id)
      rescue ActiveResource::TooManyRequests
        attempts += 1
        if attempts > RATE_LIMIT_MAX_RETRIES
          Rails.logger.warn("[OrderShippingStatusSyncService] shop_id=#{@shop.id} order_id=#{order_id} rate limit: gave up after #{RATE_LIMIT_MAX_RETRIES} waits")
          return nil
        end
        sleep(1)
      rescue ActiveResource::ResourceNotFound
        return nil
      end
    end

    def shipping_status_from_order(order)
      shipment_status = Array(order.fulfillments)
        .map { |fulfillment| fulfillment&.shipment_status.to_s.strip }
        .reject(&:blank?)
        .last
      return shipment_status if shipment_status.present?

      order.fulfillment_status.to_s.strip.presence
    end

    def touch_shop_and_result(updated_count, scanned_count)
      @shop.update_column(:last_shipping_status_pulled, Time.current)
      { updated: updated_count, scanned: scanned_count }
    end
  end
end
