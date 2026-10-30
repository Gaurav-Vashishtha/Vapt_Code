module ShopifyServices
  # Reads Shopify directly rather than customers / customer_shop_mappings:
  # those tables are global and not indexed per shop.
  class CampaignContactsPullService < ShopifyServices::GraphqlService
    PAGE_SIZE = 100
    MAX_THROTTLE_RETRIES = 6
    Throttled = Class.new(StandardError)
    LastOrderDenied = Class.new(StandardError)

    # GraphqlService.call hands the block to `new`, not `call`; we need it on
    # `call` so pages can be streamed to the caller.
    def self.call(shop, options = {}, &block)
      shop.init_session
      new(ShopifyAPI::GraphQL.client, shop, options).call(&block)
    end

    # `lastOrder` needs read_all_orders for orders older than 60 days. Without
    # it Shopify returns ACCESS_DENIED per customer, and past its error cap the
    # whole page fails ("Too many execution errors"). Dev installs don't request
    # read_all_orders (see config/initializers/shopify_app.rb), and a shop may
    # not have granted it — so we fall back to a query without lastOrder.
    LAST_ORDER_FIELD = "lastOrder { createdAt }"

    QUERY_TEMPLATE = <<~GRAPHQL.freeze
      query ($first: Int!, $after: String) {
        customers(first: $first, after: $after, sortKey: ID) {
          pageInfo { hasNextPage endCursor }
          edges {
            node {
              id
              firstName
              lastName
              phone
              email
              tags
              createdAt
              numberOfOrders
              amountSpent { amount currencyCode }
              %<last_order>s
              defaultAddress { phone }
            }
          }
        }
      }
    GRAPHQL

    QUERY = format(QUERY_TEMPLATE, last_order: LAST_ORDER_FIELD).freeze
    QUERY_WITHOUT_LAST_ORDER = format(QUERY_TEMPLATE, last_order: '').freeze

    def initialize(client, shop, options = {})
      @client = client
      @shop = shop
      @page_size = (options[:page_size] || PAGE_SIZE).to_i
    end

    def call(&block)
      query = @client.parse(QUERY)
      @with_last_order = true
      after = nil
      seen = 0

      loop do
        resp =
          begin
            fetch_page(query, after)
          rescue LastOrderDenied => e
            raise unless @with_last_order
            Rails.logger.warn "[CampaignContactsPullService] shop=#{@shop.id} lastOrder not accessible " \
                              "(read_all_orders missing?) — syncing without last order dates. #{e.message}"
            @with_last_order = false
            query = @client.parse(QUERY_WITHOUT_LAST_ORDER)
            retry
          end
        conn = resp.data&.customers
        break if conn.nil?

        page = conn.edges.map { |e| normalize(e.node) }
        seen += page.size
        block&.call(page)

        break unless conn.page_info.has_next_page
        after = conn.page_info.end_cursor
      end

      seen
    end

    private

    # Shopify's GraphQL bucket is cost-based; a 100-customer page with nested
    # lastOrder can drain it on a cold shop. Back off and retry on THROTTLED
    # instead of failing the whole sync.
    def fetch_page(query, after)
      attempts = 0
      begin
        resp = @client.query(query, variables: { 'first' => @page_size, 'after' => after })
        raw_errors = Array(resp.respond_to?(:original_hash) ? resp.original_hash&.dig('errors') : nil)
        if resp.errors&.any? || raw_errors.any?
          messages = (resp.errors&.messages&.values&.flatten || []).join('; ')
          raise Throttled, messages if messages =~ /throttl/i || raw_errors.any? { |e| e.dig('extensions', 'code') == 'THROTTLED' }

          # graphql-client only surfaces the last top-level message; the useful
          # per-field errors (with paths) are in the raw response.
          detail = raw_errors.first(3).map { |e| "#{e['message']} at #{Array(e['path']).join('.')}" }.uniq.join(' | ')
          last_order_denied = raw_errors.any? { |e| Array(e['path']).include?('lastOrder') } ||
                              messages =~ /max error limit/i
          raise LastOrderDenied, detail if last_order_denied && @with_last_order

          raise "Shopify customers query failed: #{[messages, detail].reject(&:blank?).join(' — ')}"
        end
        resp
      rescue Throttled
        attempts += 1
        raise if attempts > MAX_THROTTLE_RETRIES
        sleep(2 * attempts)
        retry
      end
    end

    def normalize(node)
      {
        shopify_id: node.id.to_s.split('/').last,
        first_name: node.first_name,
        last_name: node.last_name,
        phone: node.phone.presence || node.default_address&.phone,
        email: node.email,
        tags: Array(node.tags),
        orders_count: node.number_of_orders.to_i,
        total_spent: node.amount_spent&.amount.to_f,
        last_order_at: (@with_last_order ? parse_time(node.last_order&.created_at) : nil),
        created_at: parse_time(node.created_at)
      }
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end
  end
end
