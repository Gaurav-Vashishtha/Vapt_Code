module Whatsapp
  # Keeps the campaign contact book (whatsapp_contacts) up to date
  # incrementally, from the events that already flow through the app —
  # orders/create, customers/create and abandoned-cart creation — so
  # campaigns never have to read customers / customer_shop_mappings (which
  # span every shop and have no per-shop index). "Sync from store" remains
  # as a one-off backfill for stores that installed before this existed.
  #
  # Every call is ONE upsert via WhatsappContact.merge_rows! (never downgrades
  # existing data; counters only move up), wrapped so a failure here can never
  # break the caller's pipeline.
  module ContactBook
    module_function

    # Only shops that have connected a WhatsApp Business account get a
    # contact book maintained automatically, unless the ENV flag opens it to
    # everyone. Cached so the per-order cost is a Redis hit, not a query.
    def enabled_for?(shop)
      return false unless shop
      return true if ENV['WHATSAPP_CONTACT_BOOK_ALL_SHOPS'].to_s == 'true'

      Rails.cache.fetch("whatsapp:contact_book:enabled:#{shop.id}", expires_in: 10.minutes) do
        WhatsappAccount.where(shop_id: shop.id).exists?
      end
    rescue StandardError
      false
    end

    # orders/create webhook payload (plain Shopify REST shape).
    def record_order(shop, order)
      return unless enabled_for?(shop)
      order = order.to_h.deep_stringify_keys
      customer = order['customer'].is_a?(Hash) ? order['customer'] : {}
      phone = first_phone(
        customer['phone'], order['phone'],
        order.dig('shipping_address', 'phone'), order.dig('billing_address', 'phone')
      )
      return if phone.blank?

      name_parts = [customer['first_name'], customer['last_name']]
      name_parts = [order.dig('shipping_address', 'first_name'), order.dig('shipping_address', 'last_name')] if name_parts.compact_blank.empty?

      upsert(shop, phone, 'shopify_customer',
             first_name: name_parts[0], last_name: name_parts[1],
             email: customer['email'].presence || order['email'],
             # Shopify sends the customer's running totals on the order payload;
             # GREATEST in the merge means a replayed webhook can't double count.
             order_count: customer['orders_count'].to_i,
             total_spent: customer['total_spent'].to_f,
             last_order_at: parse_time(order['created_at']),
             source_ref: customer['id'].present? ? "cust:#{customer['id']}" : "order:#{order['id']}")
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::ContactBook] record_order failed shop=#{shop&.id} order=#{order.is_a?(Hash) ? order['id'] : '?'}: #{e.class}: #{e.message}")
      nil
    end

    # customers/create payload — accepts snake_case (REST) or camelCase (the
    # shape CustomerCreateSqsConsumerJob builds for CustomerSingleDataSaveService).
    def record_customer(shop, customer)
      return unless enabled_for?(shop)
      c = customer.to_h.deep_stringify_keys.transform_keys(&:underscore)
      phone = first_phone(c['phone'], c.dig('default_address', 'phone'))
      return if phone.blank?

      upsert(shop, phone, 'shopify_customer',
             first_name: c['first_name'], last_name: c['last_name'], email: c['email'],
             order_count: c['orders_count'].to_i, total_spent: c['total_spent'].to_f,
             source_ref: c['id'].present? ? "cust:#{c['id']}" : nil)
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::ContactBook] record_customer failed shop=#{shop&.id}: #{e.class}: #{e.message}")
      nil
    end

    # AbandonedCart row (any source: Shopify checkout, Shopflo/custom webhook).
    def record_abandoned_cart(cart)
      shop = cart.shop
      return unless enabled_for?(shop)
      phone = first_phone(cart.phone)
      return if phone.blank?

      upsert(shop, phone, 'abandoned_cart', name: cart.name, source_ref: cart.checkout_id.to_s.presence)
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::ContactBook] record_abandoned_cart failed cart=#{cart&.id}: #{e.class}: #{e.message}")
      nil
    end

    # --- helpers -----------------------------------------------------------

    def upsert(shop, phone, source, name: nil, first_name: nil, last_name: nil, email: nil,
               order_count: 0, total_spent: 0, last_order_at: nil, source_ref: nil)
      now = Time.current
      WhatsappContact.merge_rows!([{
        shop_id: shop.id, phone: phone, source: source,
        name: name.presence || [first_name, last_name].compact_blank.join(' ').presence,
        first_name: first_name.presence, last_name: last_name.presence, email: email.presence,
        tags: [], attrs: {}, order_count: order_count.to_i, total_spent: total_spent.to_f,
        last_order_at: last_order_at, source_ref: source_ref, created_at: now, updated_at: now
      }])
    end

    def first_phone(*candidates)
      candidates.each do |raw|
        phone = WhatsappContact.normalize_phone(raw)
        return phone if phone
      end
      nil
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end
  end
end
