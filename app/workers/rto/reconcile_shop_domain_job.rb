# frozen_string_literal: true

module Rto
  # Pulls orders whose Shopify `updated_at` is after our last successful incremental
  # window (`shop_domains.incremental_sync_cursor_at`), or after an explicit
  # `updated_since` override. Re-upserts into `rto_orders` (same id) so order updates
  # propagate without relying on webhooks.
  class ReconcileShopDomainJob
    include Sidekiq::Job
    sidekiq_options queue: :low, retry: 3

    PAGE_SIZE = 50
    MAX_PAGES = 200
    # Keep per-shop request rate low to avoid 429s ("Exceeded 2 calls per second for api client").
    PAGE_FETCH_SLEEP_SECONDS = (ENV.fetch("RTO_RECONCILE_PAGE_FETCH_SLEEP_SECONDS", nil).presence || "0.6").to_f
    TOO_MANY_REQUESTS_RETRY_AFTER = 5.minutes
    # Small overlap at the left bound so we do not miss orders at the boundary.
    BOUNDARY_OVERLAP = 1.second
    # First-time incremental when there is no cursor (before backfill completed).
    DEFAULT_LOOKBACK = 72.hours

    def perform(shop_domain_id, updated_since_iso = nil)
      succeeded = false
      sd = ShopDomain.find_by(id: shop_domain_id)
      return if sd.blank?

      lease = ReconcileLeaseManager.acquire_for!(sd.id)
      return unless lease

      shop = Shop.find_by(shopify_domain: sd.shopify_domain)
      return if shop.blank?

      shop.init_session

      updated_since = resolve_updated_at_min(sd, updated_since_iso)

      # REST orders list: `updated_at_min` filters by order last updated on Shopify.
      # Do not send `page` — Shopify rejects it; use Link/cursor pagination via the gem.
      page = 1
      orders = ShopifyAPI::Order.find(
        :all,
        params: {
          limit: PAGE_SIZE,
          status: "any",
          updated_at_min: updated_since.iso8601
        }
      )

      loop do
        break if orders.blank?

        orders.each do |o|
          Rto::OrderUpsertService.call(
            shopify_domain: sd.shopify_domain,
            order_payload: o,
            source: "poll",
            event_type: "orders/reconcile",
            occurred_at: Time.current
          )
        end

        break if page >= MAX_PAGES
        break unless orders.respond_to?(:next_page?) && orders.next_page?

        sleep(PAGE_FETCH_SLEEP_SECONDS) if PAGE_FETCH_SLEEP_SECONDS.positive?
        orders = orders.fetch_next_page
        page += 1
      end

      # Advance the watermark to "now" so the next run only asks for orders updated
      # after this completed sync.
      sd.update!(incremental_sync_cursor_at: Time.current, last_reconciled_at: Time.current)
      succeeded = true
    rescue ActiveResource::TooManyRequests => e
      # Back off and retry later; avoid immediately re-kicking the coordinator in ensure.
      Rails.logger.warn("[RTO] ReconcileShopDomainJob rate-limited shop=#{sd&.shopify_domain} retry_in=#{TOO_MANY_REQUESTS_RETRY_AFTER.inspect} #{e.class}: #{e.message}")
      self.class.perform_in(TOO_MANY_REQUESTS_RETRY_AFTER, shop_domain_id, updated_since_iso)
      SlackNotifyJob.perform_async(
        ":warning: (#{Rails.env})\nRTO reconcile rate-limited (429)\nShop: #{sd&.shopify_domain}\nRetryIn: #{TOO_MANY_REQUESTS_RETRY_AFTER.inspect}\n#{e.class}: #{e.message}"
      )
      nil
    rescue => e
      Rails.logger.error(
        "[RTO] ReconcileShopDomainJob failed shop_domain_id=#{shop_domain_id} shop=#{sd&.shopify_domain} " \
        "#{e.class}: #{e.message}\n#{e.backtrace&.first(20)&.join("\n")}"
      )
      SlackNotifyJob.perform_async(
        ":warning: (#{Rails.env})\nRTO reconcile failed\nShop: #{sd&.shopify_domain}\n#{e.class}: #{e.message}"
      )
      nil
    ensure
      ReconcileLeaseManager.release!(lease) if defined?(lease)
      # Keep draining the reconcile queue quickly when concurrency drops to zero.
      if succeeded && ReconcileLeaseManager.active_count.zero?
        IncrementalReconcileCoordinatorJob.perform_async
      end
    end

    private

    def resolve_updated_at_min(sd, updated_since_iso)
      if updated_since_iso.present?
        t = Time.zone.parse(updated_since_iso.to_s) rescue nil
        return t if t.present?
      end

      if sd.incremental_sync_cursor_at.present?
        t = sd.incremental_sync_cursor_at - BOUNDARY_OVERLAP
        return t
      end

      if sd.backfill_completed_at.present? && sd.backfill_started_at.present?
        return [sd.backfill_started_at - 1.hour, 1.year.ago].max
      end

      DEFAULT_LOOKBACK.ago
    end
  end
end

