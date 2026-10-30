# frozen_string_literal: true

module Whatsapp
  module Inbox
    class CustomerContext
      ORDER_LIMIT = 5

      def self.call(conversation)
        new(conversation).call
      end

      def initialize(conversation)
        @conversation = conversation
        @shop = conversation.shop
        @wa_id = conversation.customer_wa_id.to_s.gsub(/\D/, '')
        @last10 = conversation.phone_last10.to_s
      end

      def call
        orders = OrderLookup.recent(@shop, @last10, limit: ORDER_LIMIT)
        contact = load_contact
        shop_reason = PaymentLinkSender.shop_reason(@shop)
        {
          'name' => @conversation.customer_name.presence || contact&.name.presence || orders.first&.customer_name.presence,
          'wa_id' => @conversation.customer_wa_id,
          'phone_display' => ConversationSerializer.phone_display(@conversation.customer_wa_id),
          'opted_out' => opted_out?,
          'contact' => contact_json(contact),
          'orders' => orders.map { |oc| order_json(oc, shop_reason) },
          'lifetime' => lifetime_json,
          'rto_count' => rto_count(contact),
          'payment_link' => { 'available' => shop_reason.nil?, 'reason' => shop_reason&.to_s }
        }
      end

      private

      def phone_keys
        [@wa_id, @last10].reject(&:blank?).uniq
      end

      def load_contact
        return nil if phone_keys.empty?

        WhatsappContact.where(shop_id: @shop.id, phone: phone_keys).order(updated_at: :desc).first
      end

      def opted_out?
        return false if phone_keys.empty?

        WhatsappOptOut.where(shop_id: @shop.id, phone_normalized: phone_keys).exists?
      end

      def contact_json(contact)
        return nil unless contact

        {
          'order_count' => contact.order_count.to_i,
          'total_spent' => contact.total_spent.to_s,
          'cod_orders_count' => contact.cod_orders_count.to_i,
          'prepaid_orders_count' => contact.prepaid_orders_count.to_i,
          'rto_orders_count' => contact.rto_orders_count.to_i,
          'returned_orders_count' => contact.returned_orders_count.to_i
        }
      end

      def order_json(oc, shop_reason)
        numeric_id = oc.order_id.to_s[/\d+\z/]
        {
          'id' => oc.id,
          'order_id' => oc.order_id,
          'order_number' => oc.order_number,
          'amount' => oc.order_amount,
          'currency' => oc.currency,
          'is_cod' => oc.is_cod_order == true,
          'status' => oc.status,
          'status_label' => OrderLookup.status_label(oc),
          'shipping_status' => oc.shipping_status,
          'tracking_url' => oc.order_status_url.presence,
          'admin_url' => numeric_id ? "shopify://admin/orders/#{numeric_id}" : nil,
          'created_at' => oc.created_at,
          'payment_link_eligible' => shop_reason.nil? && PaymentLinkSender.order_reason(oc).nil?
        }
      end

      def lifetime_json
        totals = OrderLookup.lifetime(@shop, @last10)
        { 'orders' => totals[:orders], 'value' => totals[:value].to_s('F'), 'currency' => totals[:currency] }
      end

      def rto_count(contact)
        fallback = contact&.rto_orders_count.to_i
        shop_domain_id = ShopDomain.where(shopify_domain: @shop.shopify_domain).pick(:id)
        return fallback if shop_domain_id.nil? || @last10.blank?

        phones = [@wa_id, @last10, "0#{@last10}"].reject(&:blank?).uniq
        exact = RtoOrder.where(shop_domain_id: shop_domain_id, is_rto: true, phone_normalized: phones).count
        [exact, fallback].max
      end
    end
  end
end
