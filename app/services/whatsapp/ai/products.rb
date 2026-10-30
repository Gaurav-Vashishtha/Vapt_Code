# frozen_string_literal: true

module Whatsapp
  module Ai
    module Products
      CACHE_TTL = 10.minutes
      MAX_RESULTS = 5

      FIELDS = <<~GRAPHQL
        id
        title
        handle
        status
        description(truncateAt: 500)
        onlineStoreUrl
        productType
        priceRangeV2 { minVariantPrice { amount currencyCode } maxVariantPrice { amount currencyCode } }
        variants(first: 12) { nodes { id title price compareAtPrice availableForSale } }
      GRAPHQL

      SEARCH_QUERY = <<~GRAPHQL
        query($q: String!, $n: Int!) {
          products(first: $n, query: $q, sortKey: RELEVANCE) { nodes { #{FIELDS} } }
        }
      GRAPHQL

      NODES_QUERY = <<~GRAPHQL
        query($ids: [ID!]!) {
          nodes(ids: $ids) { ... on Product { #{FIELDS} } }
        }
      GRAPHQL

      module_function

      def search(shop, term, limit: MAX_RESULTS)
        term = term.to_s.gsub(/[^\p{L}\p{N}\s\-']/, ' ').squish.first(80)
        return [] if term.blank?

        Rails.cache.fetch("wa_ai:products:#{shop.id}:#{Digest::MD5.hexdigest(term.downcase)}", expires_in: CACHE_TTL) do
          data = ShopifyGraphql.call(shop, SEARCH_QUERY, { q: "status:active #{term}", n: limit })
          Array(data.dig('products', 'nodes')).map { |node| present(shop, node) }
        end
      rescue ShopifyGraphql::Error => e
        Rails.logger.warn("[Whatsapp::Ai::Products] search failed shop=#{shop.id}: #{e.message}")
        []
      end

      def by_ids(shop, product_ids)
        ids = Array(product_ids).filter_map { |id| gid(id) }.uniq.first(MAX_RESULTS)
        return [] if ids.empty?

        Rails.cache.fetch("wa_ai:products:ids:#{shop.id}:#{Digest::MD5.hexdigest(ids.sort.join(','))}", expires_in: CACHE_TTL) do
          data = ShopifyGraphql.call(shop, NODES_QUERY, { ids: ids })
          Array(data['nodes']).compact.select { |n| n['id'].present? }.map { |node| present(shop, node) }
        end
      rescue ShopifyGraphql::Error => e
        Rails.logger.warn("[Whatsapp::Ai::Products] lookup failed shop=#{shop.id}: #{e.message}")
        []
      end

      def gid(id)
        raw = id.to_s.strip
        return raw if raw.start_with?('gid://shopify/Product/')
        return nil unless raw.match?(/\A\d+\z/)

        "gid://shopify/Product/#{raw}"
      end

      def present(shop, node)
        variants = Array(node.dig('variants', 'nodes'))
        min = node.dig('priceRangeV2', 'minVariantPrice') || {}
        max = node.dig('priceRangeV2', 'maxVariantPrice') || {}
        {
          'title' => node['title'],
          'type' => node['productType'].presence,
          'description' => node['description'].to_s.squish.presence,
          'price' => price_label(min, max),
          'currency' => min['currencyCode'],
          'in_stock' => variants.any? { |v| v['availableForSale'] },
          'variants' => variants.map do |v|
            {
              'variant_id' => v['id'].to_s[/\d+\z/],
              'title' => v['title'],
              'price' => v['price'],
              'compare_at_price' => v['compareAtPrice'].presence,
              'available' => v['availableForSale'] == true
            }.compact
          end,
          'url' => node['onlineStoreUrl'].presence || storefront_url(shop, node['handle'])
        }.compact
      end

      def price_label(min, max)
        low = min['amount']
        high = max['amount']
        return nil if low.blank?

        low.to_f == high.to_f || high.blank? ? low.to_s : "#{low} - #{high}"
      end

      def storefront_url(shop, handle)
        return nil if handle.blank?

        "https://#{shop.primary_domain.presence || shop.shopify_domain}/products/#{handle}"
      end
    end
  end
end
