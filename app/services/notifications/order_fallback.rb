module Notifications
  # Builds a Shopify-order-shaped Hash out of the local OrderConfirmation row,
  # for the WhatsApp (BSP) payload builders when the Admin API read fails — a
  # revoked token (401) must not silently swallow a fulfilment or confirmation
  # message.
  #
  # Only the fields we actually store are filled in; everything else stays
  # absent so Whatsapp::VariableResolver substitutes its blank fallback. Returns
  # nil when there's no local record to build from, which is the one case where
  # the caller genuinely has nothing to send.
  module OrderFallback
    class << self
      def for(shop, order_id)
        return nil if shop.blank? || order_id.blank?

        oc = OrderConfirmation.find_by(shop_id: shop.id, order_id: order_id.to_s)
        return nil if oc.blank?

        from_record(oc, order_id)
      end

      def from_record(order_confirmation, order_id = nil)
        return nil if order_confirmation.blank?

        oc = order_confirmation
        first, _, last = oc.customer_name.to_s.strip.partition(' ')

        {
          'id'               => (order_id || oc.order_id).to_s,
          'name'             => oc.final_order_number.to_s,
          'order_number'     => oc.order_number.presence,
          'order_status_url' => oc.order_status_url.presence,
          'total_price'      => oc.order_amount.presence,
          'current_total_price' => oc.order_amount.presence,
          'currency'         => oc.currency.presence,
          'phone'            => oc.customer_number.presence,
          'customer'         => {
            'first_name' => first.presence,
            'last_name'  => last.presence,
            'name'       => oc.customer_name.presence,
            'phone'      => oc.customer_number.presence
          }.compact,
          'shipping_address' => {
            'name'         => oc.customer_name.presence,
            'phone'        => oc.customer_number.presence,
            'country_code' => oc.country_code.presence
          }.compact,
          # Marks the payload as reconstructed locally, so downstream logging can
          # tell a degraded send apart from a normal one.
          'from_stored_data' => true
        }.compact
      rescue StandardError => e
        Rails.logger.warn("[order_fallback] could not build fallback order=#{order_id}: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
