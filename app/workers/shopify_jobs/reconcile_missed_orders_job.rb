module ShopifyJobs
  class ReconcileMissedOrdersJob < ApplicationJob
    sidekiq_options queue: 'administration', retry: 1

    # Overlap beyond the 1h cadence so an order created right on a run boundary
    # isn't missed by both runs. Reprocessing is idempotent (acquire_lock +
    # find_or_initialize_by), so re-checking the same order twice is harmless.
    DEFAULT_WINDOW_MINUTES = 90
    ORDERS_PAGE_SIZE = 250
    MAX_PAGES = 4
    MAX_REPROCESS_PER_SHOP = 200

    def perform(window_minutes = DEFAULT_WINDOW_MINUTES, auto_reprocess = true)
      return if ENV['RECONCILE_MISSED_ORDERS_ENABLED'] == 'false'

      since_iso = (Time.now.utc - window_minutes.to_i.minutes).iso8601
      shops = Shop.joins(:setting).where(settings: { partial_payment_enabled: true })

      scanned_shops = 0
      total_orders = 0
      total_missing = 0
      reprocessed = 0
      error_count = 0
      report_lines = []

      shops.find_each do |shop|
        begin
          order_ids = recent_order_ids(shop, since_iso)
          next if order_ids.empty?

          scanned_shops += 1
          total_orders += order_ids.size
          existing = OrderConfirmation.where(shop_id: shop.id, order_id: order_ids).pluck(:order_id).map(&:to_s)
          missing = order_ids - existing
          next if missing.empty?

          total_missing += missing.size
          report_lines << "#{shop.shopify_domain}: #{missing.size}/#{order_ids.size} missing#{missing.size > MAX_REPROCESS_PER_SHOP ? " (capped at #{MAX_REPROCESS_PER_SHOP})" : ''} — #{missing.first(20).join(', ')}"

          next unless auto_reprocess

          missing.first(MAX_REPROCESS_PER_SHOP).each do |oid|
            ReprocessMissedOrderJob.perform_async(shop.id, oid)
            reprocessed += 1
          end
        rescue => e
          error_count += 1
          Rails.logger.error("[ReconcileMissedOrders] shop=#{shop.id} #{shop.shopify_domain} failed: #{e.class}: #{e.message}")
          report_lines << "#{shop.shopify_domain}: ERROR #{e.class}: #{e.message}"
        end
      end

      mode = auto_reprocess ? "reprocessed #{reprocessed}" : "dry-run (no reprocess)"
      icon = total_missing.zero? && error_count.zero? ? ":white_check_mark:" : ":mag:"
      summary =
        "#{icon} ReconcileMissedOrders (#{Rails.env}) window=#{window_minutes}m — " \
        "checked #{total_orders} order(s) across #{scanned_shops} active shop(s); " \
        "#{total_missing} missing, #{error_count} shop error(s); #{mode}"
      summary += "\n#{report_lines.join("\n")}" if report_lines.any?

      SlackNotifyJob.perform_async(summary)
    end

    private

    def recent_order_ids(shop, since_iso)
      shop.init_session
      client = ::ShopifyAPI::GraphQL.client

      query = client.parse <<-'GRAPHQL'
        query ($q: String!, $cursor: String, $pageSize: Int!) {
          orders(first: $pageSize, query: $q, after: $cursor, sortKey: CREATED_AT) {
            edges { node { id } }
            pageInfo { hasNextPage endCursor }
          }
        }
      GRAPHQL

      ids = []
      cursor = nil
      pages = 0

      loop do
        resp = client.query(
          query,
          variables: { q: "created_at:>='#{since_iso}'", cursor: cursor, pageSize: ORDERS_PAGE_SIZE }
        )

        if resp.respond_to?(:errors) && resp.errors&.any?
          Rails.logger.warn("[ReconcileMissedOrders] graphql errors shop=#{shop.id}: #{resp.errors.inspect}")
          break
        end

        orders = resp&.data&.orders
        break unless orders

        Array(orders.edges).each do |edge|
          gid = edge&.node&.id
          ids << gid.split('/').last if gid.present?
        end

        pages += 1
        break unless orders.page_info&.has_next_page
        break if pages >= MAX_PAGES

        cursor = orders.page_info.end_cursor
      end

      ids
    end
  end
end
