# frozen_string_literal: true

module Whatsapp
  module Ai
    module ShopifyOrders
      FIELDS = {
        'id' => 'id',
        'name' => 'name',
        'createdAt' => 'createdAt',
        'cancelledAt' => 'cancelledAt',
        'displayFinancialStatus' => 'displayFinancialStatus',
        'displayFulfillmentStatus' => 'displayFulfillmentStatus',
        'paymentGatewayNames' => 'paymentGatewayNames',
        'statusPageUrl' => 'statusPageUrl',
        'phone' => 'phone',
        'customer' => 'customer { phone }',
        'shippingAddress' => 'shippingAddress { phone city province }',
        'billingAddress' => 'billingAddress { phone }',
        'totalPriceSet' => 'totalPriceSet { shopMoney { amount currencyCode } }',
        'lineItems' => 'lineItems(first: 10) { nodes { title quantity variantTitle } }',
        'fulfillments' => 'fulfillments(first: 5) { displayStatus estimatedDeliveryAt trackingInfo(first: 3) { company number url } }'
      }.freeze
      DENIED = /(?:Access denied for|not approved to use the) (\w+) field/
      PII_FIELDS = %w[phone customer billingAddress shippingAddress].freeze
      DENY_GROUPS = {
        'phone' => PII_FIELDS, 'email' => PII_FIELDS, 'firstName' => PII_FIELDS, 'lastName' => PII_FIELDS,
        'address1' => %w[shippingAddress billingAddress], 'city' => %w[shippingAddress billingAddress],
        'province' => %w[shippingAddress billingAddress], 'zip' => %w[shippingAddress billingAddress]
      }.freeze
      MAX_RETRIES = 6

      def self.query(fields)
        <<~GRAPHQL
          query($q: String!) {
            orders(first: 3, query: $q, sortKey: CREATED_AT, reverse: true) {
              nodes { #{fields.values.join(' ')} }
            }
          }
        GRAPHQL
      end

      module_function

      def find_by_number(shop, digits)
        data = fetch(shop, { q: "name:#{digits}" })
        nodes = Array(data.dig('orders', 'nodes'))
        nodes.find { |n| n['name'].to_s.gsub(/\D/, '') == digits } || nodes.first
      end

      def fetch(shop, variables)
        cache_key = "wa_ai:order_fields_denied:#{shop.id}"
        denied = Array(Rails.cache.read(cache_key))
        attempts = 0
        begin
          ShopifyGraphql.call(shop, query(FIELDS.except(*denied)), variables)
        rescue ShopifyGraphql::Error => e
          field = e.message[DENIED, 1]
          drop = DENY_GROUPS[field] || (FIELDS.key?(field) ? [field] : [])
          drop -= %w[id name]
          raise if drop.empty? || (drop - denied).empty? || (attempts += 1) > MAX_RETRIES

          denied |= drop
          Rails.cache.write(cache_key, denied, expires_in: 1.day)
          retry
        end
      end

      def phones(node)
        [node['phone'], node.dig('customer', 'phone'), node.dig('shippingAddress', 'phone'), node.dig('billingAddress', 'phone')]
          .map { |p| Whatsapp::Inbox::OrderLookup.last10(p) }
          .select { |p| p.length >= 10 }
          .uniq
      end

      def present(node, timezone)
        gateways = Array(node['paymentGatewayNames'])
        cod = gateways.any? { |g| g.to_s.match?(/cash on delivery|\bcod\b/i) }
        tracking = Array(node['fulfillments']).flat_map do |f|
          Array(f['trackingInfo']).map { |t| t.slice('company', 'number', 'url').compact }
        end.reject(&:empty?)
        money = node.dig('totalPriceSet', 'shopMoney') || {}
        {
          'order_number' => node['name'],
          'placed_at' => (Time.zone.parse(node['createdAt'].to_s)&.in_time_zone(timezone)&.strftime('%d %b %Y') rescue nil),
          'amount' => [money['currencyCode'], money['amount']].compact.join(' ').presence,
          'payment' => cod ? 'Cash on delivery' : 'Prepaid',
          'payment_status' => node['displayFinancialStatus'].to_s.humanize.presence,
          'fulfillment_status' => node['displayFulfillmentStatus'].to_s.humanize.presence,
          'cancelled' => node['cancelledAt'].present?,
          'shipments' => Array(node['fulfillments']).map { |f| f['displayStatus'].to_s.humanize }.compact_blank.presence,
          'estimated_delivery' => Array(node['fulfillments']).filter_map { |f| f['estimatedDeliveryAt'] }.first,
          'tracking' => tracking.presence,
          'order_status_url' => node['statusPageUrl'].presence,
          'ship_to_city' => [node.dig('shippingAddress', 'city'), node.dig('shippingAddress', 'province')].compact.join(', ').presence,
          'items' => Array(node.dig('lineItems', 'nodes')).map do |li|
            [li['title'], li['variantTitle'].presence].compact.join(' - ') + " x#{li['quantity']}"
          end
        }.compact
      end
    end
  end
end
