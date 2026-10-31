module ShopifyServices
  # Reads a Shopify order for a customer notification (order confirmation /
  # fulfilment SMS + WhatsApp) WITHOUT letting an Admin API failure cancel the
  # message.
  #
  # Returns the ShopifyAPI::Order on success and `nil` on ANY failure — a 401
  # (token revoked out of band: reinstall, scope change, rotated secret), a 403
  # (legacy non-expiring token), a 404, a 429 that outlived its retries, a 5xx
  # or a timeout. `nil` means "Shopify is unreadable for this order right now";
  # every caller falls back to what the local OrderConfirmation row holds plus
  # Notifications::Defaults, so the customer still gets the message.
  #
  # On a 401/403 we first try to rotate the offline token via its refresh token
  # and retry once — that silently self-heals the common case. Only when the
  # rotation is impossible do we alert (throttled to once/shop/day) and return
  # nil; the merchant re-opening the app re-mints the token.
  #
  #   order = ShopifyServices::SafeOrderReader.find(shop, order_confirmation.order_id)
  class SafeOrderReader < ApplicationService
    MAX_THROTTLE_RETRIES = 3
    THROTTLE_SLEEP = 10

    def initialize(shop, order_id)
      @shop = shop
      @order_id = order_id
    end

    def call
      self.class.find(@shop, @order_id)
    end

    class << self
      def find(shop, order_id)
        return nil if shop.blank? || order_id.blank?

        throttle_retries = 0
        unauthorized_retries = 0

        shop.init_session
        begin
          ShopifyAPI::Order.find(order_id)
        rescue ActiveResource::TooManyRequests
          throttle_retries += 1
          if throttle_retries <= MAX_THROTTLE_RETRIES
            sleep(THROTTLE_SLEEP)
            retry
          end
          warn_unreadable(shop, order_id, 'throttled by Shopify')
          nil
        rescue ActiveResource::UnauthorizedAccess, ActiveResource::ForbiddenAccess => e
          unauthorized_retries += 1
          if unauthorized_retries == 1 &&
             ShopifyServices::OfflineTokenService.recover_from_unauthorized!(shop, failed_token: shop.shopify_token)
            shop.init_session
            retry
          end
          shop.notify_token_reauth_needed_once(
            "#{e.class} on Order.find(order_id=#{order_id}) — notification sent from stored data instead"
          )
          warn_unreadable(shop, order_id, e.class.to_s)
          nil
        rescue ActiveResource::ResourceNotFound
          warn_unreadable(shop, order_id, 'order not found')
          nil
        rescue StandardError => e
          warn_unreadable(shop, order_id, "#{e.class}: #{e.message}")
          nil
        end
      end

      # Same read, as a plain Hash (Shopify order shape) for the BSP/WhatsApp
      # payload builders. nil when the order can't be read.
      def find_hash(shop, order_id)
        order = find(shop, order_id)
        return nil if order.blank?

        hash = JSON.parse(order.to_json)
        hash = hash['order'] if hash.is_a?(Hash) && hash.key?('order') && hash.size == 1
        hash.is_a?(Hash) && hash['id'].present? ? hash : nil
      rescue StandardError => e
        warn_unreadable(shop, order_id, "unparseable response #{e.class}")
        nil
      end

      private

      def warn_unreadable(shop, order_id, reason)
        Rails.logger.warn(
          "[safe_order_read] shop=#{shop&.shopify_domain} order=#{order_id} unreadable (#{reason}) — falling back to stored data"
        )
      end
    end
  end
end
