# frozen_string_literal: true

module Whatsapp
  module Ai
    class ContextBuilder
      ORDER_LIMIT = 5
      HISTORY_LIMIT = 16
      CART_EVENTS = %w[abandoned_cart cart_abandoned browse_abandoned].freeze
      CART_LOOKBACK = 7.days
      LAST10_SQL = "right(regexp_replace((recipient)::text, '\\D'::text, ''::text, 'g'::text), 10)"
      AWAITING = ::Whatsapp::ContactOrderStats::UNCONFIRMED_COD_STATUSES

      attr_reader :conversation, :shop

      def self.call(conversation, history: nil)
        new(conversation, history: history).call
      end

      def initialize(conversation, history: nil)
        @conversation = conversation
        @shop = conversation.shop
        @history = history
      end

      def call
        orders = load_orders
        {
          'store' => store_json,
          'customer' => customer_json(orders),
          'orders' => orders.map { |oc| order_json(oc) },
          'cart' => cart_json,
          'payment_link_available' => Whatsapp::Inbox::PaymentLinkSender.shop_reason(shop).nil?,
          'payment_link_note' => payment_link_note(Whatsapp::Inbox::PaymentLinkSender.shop_reason(shop)),
          'now' => Time.current.in_time_zone(Whatsapp::ShopTimezone.for(shop)).strftime('%a %d %b %Y, %H:%M %Z'),
          'history' => @history || history_json,
          '_orders' => orders
        }
      end

      def store_json
        {
          'name' => Whatsapp::Inbox::ReplyVariables.store_name(conversation, shop),
          'website' => "https://#{storefront_host}",
          'currency' => shop.currency.presence
        }.compact
      end

      def storefront_host
        shop.primary_domain.to_s.sub(%r{\Ahttps?://}, '').split('/').first.presence || shop.shopify_domain
      end

      def order_json(oc)
        {
          'order_number' => display_number(oc.order_number),
          'placed_at' => oc.created_at&.in_time_zone(Whatsapp::ShopTimezone.for(shop))&.strftime('%d %b %Y'),
          'amount' => [oc.currency.presence, oc.order_amount.presence].compact.join(' ').presence,
          'payment' => oc.is_cod_order ? 'Cash on delivery' : 'Prepaid',
          'status' => Whatsapp::Inbox::OrderLookup.status_label(oc).presence,
          'awaiting_cod_confirmation' => oc.is_cod_order == true && AWAITING.include?(oc.status.to_s),
          'shipping_status' => oc.shipping_status.presence,
          'tracking_url' => oc.order_status_url.presence,
          'payment_link_eligible' => Whatsapp::Inbox::PaymentLinkSender.order_reason(oc).nil?,
          'payment_link_note' => order_payment_note(Whatsapp::Inbox::PaymentLinkSender.order_reason(oc))
        }.compact
      end

      def payment_link_note(reason)
        case reason
        when nil then nil
        when :paused then 'Online payment links are paused by the store right now.'
        else 'This store does not offer online payment links on WhatsApp. Orders are cash on delivery.'
        end
      end

      def order_payment_note(reason)
        case reason
        when :not_cod then 'Already paid online.'
        when :not_pending then 'Already confirmed for cash on delivery; an online payment link can no longer be sent. The customer pays cash at delivery.'
        end
      end

      def display_number(number)
        value = number.to_s.strip
        return nil if value.blank?

        value.start_with?('#') ? value : "##{value}"
      end

      private

      def load_orders
        Whatsapp::Inbox::OrderLookup.recent(shop, conversation.phone_last10, limit: ORDER_LIMIT)
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Ai::ContextBuilder] orders failed conv=#{conversation.id}: #{e.class}: #{e.message}")
        []
      end

      def customer_json(orders)
        name = conversation.customer_name.to_s.squish.presence || orders.first&.customer_name.to_s.squish.presence
        { 'name' => name, 'first_name' => name.to_s.split(' ').first, 'orders_count' => orders.size }.compact
      end

      def cart_json
        log = cart_log
        return nil unless log

        snapshot = log.payload_snapshot.is_a?(Hash) ? log.payload_snapshot : {}
        root = snapshot['checkout'] || snapshot['cart'] || snapshot['browse'] || {}
        items = Array(root['line_items']).select { |i| i.is_a?(Hash) }.first(8)
        product_ids = items.map { |i| i['product_id'] }.compact
        products = Products.by_ids(shop, product_ids)
        {
          'type' => log.event_type_key == 'browse_abandoned' ? 'viewed_product' : 'abandoned_cart',
          'sent_at' => log.created_at&.in_time_zone(Whatsapp::ShopTimezone.for(shop))&.strftime('%d %b %Y %H:%M'),
          'checkout_url' => (root['abandoned_checkout_url'].presence || root['cart_url'].presence || root['product_url'].presence),
          'total' => root['total_price'].presence,
          'items' => items.map { |i| { 'title' => i['title'], 'quantity' => i['quantity'], 'price' => i['price'] }.compact },
          'viewed_product' => root['product_name'].presence && {
            'title' => root['product_name'], 'price' => root['product_price'], 'url' => root['product_url']
          }.compact,
          'already_sent_discount' => snapshot['discount'].is_a?(Hash) ? snapshot['discount'].slice('code', 'formatted').presence : nil,
          'product_details' => products.presence
        }.compact
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Ai::ContextBuilder] cart failed conv=#{conversation.id}: #{e.class}: #{e.message}")
        nil
      end

      def cart_log
        return nil if conversation.whatsapp_account_id.nil? || conversation.phone_last10.blank?

        WhatsappMessageLog.where(whatsapp_account_id: conversation.whatsapp_account_id, event_type_key: CART_EVENTS)
                          .where("#{LAST10_SQL} = ?", conversation.phone_last10.to_s)
                          .where('created_at > ?', CART_LOOKBACK.ago)
                          .where.not(status: %w[failed dropped])
                          .order(created_at: :desc)
                          .first
      end

      def history_json
        return [] unless conversation.persisted?

        messages = WhatsappConversationMessage.where(whatsapp_conversation_id: conversation.id)
                                   .where.not(kind: %w[reaction system])
                                   .order(occurred_at: :desc, id: :desc)
                                   .limit(HISTORY_LIMIT)
                                   .to_a.reverse
        image_ids = messages.select { |m| m.inbound? && m.kind.to_s == 'image' }
                            .last(MediaReader::IMAGE_LIMIT).map(&:id)
        messages.filter_map { |m| history_item(m, with_image: image_ids.include?(m.id)) }
      end

      def history_item(message, with_image: false)
        text = message.body.to_s.strip
        image = with_image ? MediaReader.image_data_url(message) : nil
        if message.inbound? && message.kind.to_s == 'audio'
          voice = MediaReader.transcript(message)
          text = voice.present? ? "[Voice note] #{voice}" : '[Voice note - not transcribed]'
        elsif message.inbound? && message.kind.to_s == 'image'
          text = image ? (text.presence || '[Photo attached]') : "[Photo - not readable]#{" #{text}" if text.present?}"
        end
        text = "[#{WhatsappConversationMessage.preview_for(kind: message.kind, body: nil, content: message.content, file_name: message.media_file_name)}]" if text.blank?
        return nil if text.blank?

        role = message.inbound? ? 'customer' : 'store'
        item = { 'role' => role, 'source' => message.source, 'kind' => message.kind, 'text' => text.truncate(2000) }
        item['image_url'] = image if image
        item
      end
    end
  end
end
