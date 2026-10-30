module ShopifyServices
  # Cancels a Shopify order on behalf of a buyer who tapped "Cancel" on the
  # COD verification WhatsApp message. Mirrors the same Shopify-side actions
  # ShopifyJobs::AutoCancelJob takes for time-out cancels:
  #   - order.cancel(reason: 'declined', restock: true)
  #   - void any sale transactions
  # Safe-no-op if the order is already paid, fulfilled, or cancelled.
  class CancelCodOrderService
    # `code` is a stable symbol callers can branch on without string-matching
    # `reason`: :cancelled, :not_found, :already_paid, :already_fulfilled,
    # :already_cancelled, :error.
    Result = Struct.new(:cancelled, :code, :reason, :error, keyword_init: true)

    def self.call(shop:, order_id:)
      new(shop: shop, order_id: order_id).call
    end

    def initialize(shop:, order_id:)
      @shop = shop
      @order_id = order_id
    end

    def call
      shop.init_session
      order = ::ShopifyAPI::Order.find(order_id)
      return Result.new(cancelled: false, code: :not_found, reason: 'order not found') unless order

      if order.financial_status.to_s == 'paid'
        return Result.new(cancelled: false, code: :already_paid, reason: 'already paid — refusing to auto-cancel')
      end
      if order.fulfillment_status.to_s == 'fulfilled'
        return Result.new(cancelled: false, code: :already_fulfilled, reason: 'already fulfilled — refusing to auto-cancel')
      end
      if order.cancelled_at.present?
        return Result.new(cancelled: false, code: :already_cancelled, reason: 'already cancelled')
      end

      restock = order.fulfillment_status.to_s != 'restocked'
      order.cancel(email: true, reason: 'declined', restock: restock)

      void_sale_transactions(order)

      Result.new(cancelled: true, code: :cancelled, reason: 'cancelled via BSP COD verification')
    rescue => e
      Rails.logger.warn("[cod_cancel] shop=#{shop.id} order=#{order_id} failed: #{e.class}: #{e.message}")
      Result.new(cancelled: false, code: :error, error: "#{e.class}: #{e.message}")
    end

    private

    attr_reader :shop, :order_id

    # Best-effort voiding of any sale-kind transactions. Failures are swallowed
    # (logged) so a transaction-void hiccup doesn't roll back the order cancel.
    def void_sale_transactions(order)
      Array(order.transactions).each do |t|
        next unless t.respond_to?(:kind) && t.kind == 'sale'

        void = ::ShopifyAPI::Transaction.new(order_id: order.id)
        void.order_id = order.id
        void.currency = t.currency
        void.amount = t.amount
        void.kind = 'void'
        void.parent_id = t.id
        void.save
      end
    rescue => e
      Rails.logger.info("[cod_cancel] void_sale_transactions order=#{order_id} swallowed: #{e.message}")
    end
  end
end
