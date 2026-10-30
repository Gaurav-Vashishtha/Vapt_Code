module Whatsapp
  # Single place that sends the post-verification "order confirmed" message.
  # Called from every path that marks a COD order verified (BSP Confirm tap,
  # /order_confirmations/confirm, manual confirm) so all of them behave the
  # same:
  #
  #   1. BSP `order_created` template when the shop has it bound on a
  #      sendable number. DispatchEventJob dedups on the order id, so a shop
  #      that already got order_created at placement (no cod_verification
  #      binding) doesn't get it twice. If the shop has also bound the
  #      `order_created_partial` sibling event, DispatchEventJob picks
  #      whichever one applies per order (partial payment vs normal) — this
  #      notifier only needs to know a BSP template is configured at all.
  #   2. Otherwise the legacy MSG91 confirmation (WhatsApp / SMS) when the
  #      shop has that enabled.
  #
  # A paused binding means silence: no MSG91 fallback.
  #
  # Returns :bsp, :msg91, :paused or nil (nothing configured / no payload available).
  class OrderConfirmationNotifier < ApplicationService
    def initialize(shop:, order_confirmation:, payload_snapshot: nil)
      @shop = shop
      @oc = order_confirmation
      @payload_snapshot = payload_snapshot
    end

    def call
      return nil if shop.nil? || oc.nil?

      normal_binding  = shop.whatsapp_template_bindings.find_by(event_type_key: 'order_created')
      partial_binding = shop.whatsapp_template_bindings.find_by(event_type_key: 'order_created_partial')
      bound = [normal_binding, partial_binding].compact
      return paused! if bound.any? && bound.all?(&:paused?)

      if normal_binding || partial_binding
        payload = bsp_payload
        if payload.nil?
          Rails.logger.warn("[order_confirmation_notifier] shop=#{shop.id} order=#{oc.order_id} no order payload for BSP order_created — falling back to MSG91")
        else
          # DispatchEventJob only routes to order_created_partial for partial
          # orders; anything else needs the plain order_created binding. Pick
          # the binding that will actually be used so a shop that bound only
          # the partial template still falls back to MSG91 for normal orders
          # instead of being silently dropped inside DispatchEventJob.
          partial = partial_binding && Whatsapp::DispatchEventJob.new.send(:partial_payment_order?, payload, shop)
          binding = partial ? partial_binding : normal_binding
          return paused! if binding&.paused?

          account = binding && (binding.whatsapp_account || shop.default_whatsapp_account)
          if binding && account&.ready_to_send?
            Whatsapp::DispatchEventJob.perform_async('order_created', shop.shopify_domain, payload)
            return :bsp
          end
        end
      end

      if shop.setting&.confirmation_sms_enabled || shop.setting&.confirmation_whatsapp
        NetworkJobs::SendConfirmationSmsJob.perform_async(shop.id, oc.id)
        return :msg91
      end

      Rails.logger.warn("[order_confirmation_notifier] shop=#{shop.id} order=#{oc.order_id} nothing sent — no sendable BSP order_created binding and MSG91 confirmation disabled")
      nil
    end

    private

    attr_reader :shop, :oc, :payload_snapshot

    def paused!
      Rails.logger.info("[order_confirmation_notifier] shop=#{shop.id} order=#{oc.order_id} order_created paused — nothing sent")
      :paused
    end

    # Order payload for DispatchEventJob, in the { 'order' => {...} } shape.
    # Preference: the snapshot the caller already has (BSP reply path) →
    # the cod_verification log stored for this order → a fresh Shopify read.
    def bsp_payload
      from_snapshot(payload_snapshot) || from_verification_log || from_shopify
    end

    def from_snapshot(snap)
      return nil unless snap.is_a?(Hash)

      snap = snap.deep_stringify_keys
      return snap if snap['order'].is_a?(Hash) && snap['order']['id'].present?
      return { 'order' => snap } if snap['id'].present? && snap.key?('line_items')

      nil
    end

    def from_verification_log
      log = WhatsappMessageLog
              .where(shop_id: shop.id, event_type_key: 'cod_verification', source_external_id: oc.order_id.to_s)
              .recent
              .first
      from_snapshot(log&.payload_snapshot)
    end

    def from_shopify
      return nil if oc.order_id.blank? || oc.order_id.to_s == '1234567890'

      shop.init_session
      order = ShopifyAPI::Order.find(oc.order_id)
      hash = JSON.parse(order.to_json)
      hash = hash['order'] if hash.is_a?(Hash) && hash.key?('order') && hash.size == 1
      hash.is_a?(Hash) && hash['id'].present? ? { 'order' => hash } : nil
    rescue StandardError => e
      Rails.logger.warn("[order_confirmation_notifier] shopify fetch failed shop=#{shop.id} order=#{oc.order_id}: #{e.class}: #{e.message}")
      nil
    end
  end
end
