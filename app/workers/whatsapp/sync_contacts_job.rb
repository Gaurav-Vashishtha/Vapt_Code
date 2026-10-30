module Whatsapp
  # Pulls abandoned-cart customers (from our per-shop abandoned_carts table)
  # and Shopify customers (from the Shopify Admin API — never from the global
  # customers / customer_shop_mappings tables) into the contact book.
  # Manual-only (merchant clicks "Sync from store"); no cron.
  #
  # Progress + outcome are written to Redis so the Contacts page can poll and
  # actually tell the merchant what happened (running / done with counts /
  # failed with the error) instead of a fire-and-forget "Sync started".
  class SyncContactsJob < ApplicationJob
    sidekiq_options queue: 'whatsapp_bsp_campaign', retry: 1
    BATCH = 500
    STATUS_TTL = 24.hours.to_i
    # A "running" status older than this is treated as stale (worker died,
    # deploy restart) so the merchant can start another sync.
    STALE_AFTER = 20.minutes

    def self.status_key(shop_id) = "whatsapp:contacts:sync:#{shop_id}"

    def self.status(shop_id)
      raw = Sidekiq.redis { |r| r.get(status_key(shop_id)) }
      return nil if raw.blank?
      data = JSON.parse(raw)
      if data['status'] == 'running' && data['started_at'].present? &&
         Time.zone.parse(data['started_at']) < STALE_AFTER.ago
        data['status'] = 'stale'
      end
      data
    rescue StandardError
      nil
    end

    def self.running?(shop_id)
      %w[queued running].include?(status(shop_id)&.dig('status'))
    end

    def self.mark(shop_id, **attrs)
      current = status(shop_id) || {}
      current.delete('status') if current['status'] == 'stale'
      data = current.merge(attrs.transform_keys(&:to_s)).merge('updated_at' => Time.current.iso8601)
      Sidekiq.redis { |r| r.set(status_key(shop_id), data.to_json, ex: STATUS_TTL) }
      data
    rescue StandardError => e
      Rails.logger.warn("[Whatsapp::SyncContactsJob] status write failed shop=#{shop_id}: #{e.message}")
      nil
    end

    def perform(shop_id)
      shop = Shop.find_by(id: shop_id)
      return unless shop

      self.class.mark(shop.id, status: 'running', started_at: Time.current.iso8601, error: nil,
                               carts: 0, customers: 0, upserted: 0)
      now = Time.current
      carts = sync_abandoned_carts(shop, now)
      self.class.mark(shop.id, carts: carts)
      customers = sync_customers(shop, now)
      self.class.mark(shop.id, customers: customers)
      apply_opt_outs(shop, now)

      total = WhatsappContact.where(shop_id: shop.id).count
      self.class.mark(shop.id, status: 'done', finished_at: Time.current.iso8601,
                               carts: carts, customers: customers, upserted: carts + customers, total: total)
      Rails.logger.info("[Whatsapp::SyncContactsJob] shop=#{shop.id} carts=#{carts} customers=#{customers} total=#{total}")
      ContactOrderStatsJob.perform_async('full', shop.id)
    rescue => e
      Rails.logger.error("[Whatsapp::SyncContactsJob] shop=#{shop_id} #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
      self.class.mark(shop_id, status: 'failed', finished_at: Time.current.iso8601,
                               error: "#{e.class}: #{e.message}".truncate(500))
      SlackNotifyJob.perform_async(
        ":x: WhatsApp contact sync failed (#{Rails.env}) shop=#{shop&.shopify_domain || shop_id}: #{e.class}: #{e.message.to_s.truncate(300)}"
      ) rescue nil
      # Surface in Sidekiq (retry once, then the Dead set) instead of swallowing.
      raise
    end

    private

    def sync_abandoned_carts(shop, now)
      rows = []
      count = 0
      AbandonedCart.where(shop_id: shop.id).find_each(batch_size: 1000) do |cart|
        phone = WhatsappContact.normalize_phone(cart.phone)
        next unless phone
        rows << row(shop.id, phone, 'abandoned_cart', now, name: cart.name, source_ref: cart.checkout_id.to_s)
        count += flush(rows) if rows.size >= BATCH
      end
      count + flush(rows)
    end

    # Customers come straight from Shopify (Admin GraphQL, paged), NOT from
    # customers / customer_shop_mappings. Progress is written per page so the
    # UI's "N customers so far" moves on big stores.
    def sync_customers(shop, now)
      count = 0
      ShopifyServices::CampaignContactsPullService.call(shop) do |page|
        rows = page.filter_map do |c|
          phone = WhatsappContact.normalize_phone(c[:phone])
          next unless phone
          row(shop.id, phone, 'shopify_customer', now,
              name: [c[:first_name], c[:last_name]].compact_blank.join(' ').presence,
              first_name: c[:first_name], last_name: c[:last_name], email: c[:email],
              order_count: c[:orders_count], total_spent: c[:total_spent],
              source_ref: "cust:#{c[:shopify_id]}")
            .merge(last_order_at: c[:last_order_at],
                   # Shopify customer tags become contact tags so segments can
                   # target them (e.g. tag "vip" set in Shopify admin).
                   tags: WhatsappContact.sanitize_tags(c[:tags]))
        end
        count += flush(rows)
        self.class.mark(shop.id, customers: count)
      end
      count
    end

    def apply_opt_outs(shop, now)
      opted = WhatsappOptOut.where(shop_id: shop.id).pluck(:phone_normalized)
      return if opted.empty?
      WhatsappContact.where(shop_id: shop.id, phone: opted, subscribed: true)
                     .update_all(subscribed: false, updated_at: now)
    end

    def row(shop_id, phone, source, now, name: nil, first_name: nil, last_name: nil, email: nil,
            order_count: 0, total_spent: 0, source_ref: nil)
      { shop_id: shop_id, phone: phone, source: source, name: name,
        first_name: first_name, last_name: last_name, email: email,
        tags: [], attrs: {}, order_count: order_count, total_spent: total_spent,
        source_ref: source_ref, created_at: now, updated_at: now }
    end

    def flush(rows)
      n = WhatsappContact.merge_rows!(rows)
      rows.clear
      n
    end
  end
end
