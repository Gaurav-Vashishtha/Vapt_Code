# frozen_string_literal: true

require "bigdecimal"

module CodForm
  # Variant prices, stock and collections straight from Shopify (ARCHITECTURE.md F.1).
  # The storefront never supplies a price: every quote and every order is priced from here.
  #
  # Also hosts `admin_query`, the one place the form services run Admin GraphQL from
  # (same idiom as the existing ShopifyServices::* classes: shop.init_session,
  # ShopifyAPI::GraphQL.client, client.parse, client.query).
  class CatalogService
    VARIANT_TTL = 60.seconds
    SHOP_INFO_TTL = 1.hour
    MAX_LINES = 50
    MAX_QUANTITY = 9_999
    MAX_PROPERTIES = 20

    VARIANTS_QUERY = <<~GRAPHQL
      query ($ids: [ID!]!, $country: CountryCode!) {
        nodes(ids: $ids) {
          __typename
          ... on ProductVariant {
            id
            title
            price
            compareAtPrice
            availableForSale
            inventoryQuantity
            inventoryPolicy
            taxable
            image { url }
            contextualPricing(context: {country: $country}) {
              price { amount currencyCode }
              compareAtPrice { amount }
            }
            inventoryItem {
              tracked
              requiresShipping
              measurement { weight { value unit } }
            }
            product {
              id
              title
              vendor
              isGiftCard
              featuredImage { url }
              collections(first: 50) { nodes { id } }
            }
          }
        }
      }
    GRAPHQL

    SHOP_QUERY = <<~GRAPHQL
      query {
        shop {
          currencyCode
          taxesIncluded
          currencyFormats { moneyFormat }
        }
      }
    GRAPHQL

    GRAMS_PER_UNIT = { "GRAMS" => 1.0, "KILOGRAMS" => 1000.0, "OUNCES" => 28.349523125, "POUNDS" => 453.59237 }.freeze

    @geo_cache = {}
    @geo_mutex = Mutex.new

    class << self
      # items: [{"variant_id","quantity","properties"}] (string keys, as sent by the browser).
      # Returns the E.7 line hashes in the same order. Raises CodForm::Errors::InvalidItem.
      def lines(shop, items, country:)
        clean = sanitize_items(items)
        raise CodForm::Errors::InvalidItem, "empty" if clean.empty?

        catalog = variants(shop, clean.map { |item| item["variant_id"] }, country: country)
        clean.each_with_index.map do |item, index|
          variant = catalog[item["variant_id"]]
          raise CodForm::Errors::InvalidItem, "unknown_variant" if variant.nil?

          variant.merge("key" => "l#{index}", "quantity" => item["quantity"], "properties" => item["properties"])
        end
      end

      # {"<variant id>" => line hash without key/quantity/properties}. Unknown ids are absent.
      def variants(shop, variant_ids, country:)
        ids = Array(variant_ids).map(&:to_s).select { |id| id.match?(/\A\d{1,20}\z/) }.uniq
        return {} if ids.empty?

        country_code = resolve_country(shop, country)
        keys = ids.to_h { |id| [id, variant_cache_key(shop.id, id, country_code)] }
        cached = CodForm::Cache.store.read_multi(*keys.values)
        result = {}
        missing = []
        ids.each do |id|
          hit = cached[keys[id]]
          hit.is_a?(Hash) ? result[id] = hit : missing << id
        end

        fetch_variants(shop, missing, country_code).each do |id, line|
          CodForm::Cache.store.write(keys[id], line, expires_in: VARIANT_TTL)
          result[id] = line
        end
        result
      end

      # {"currency","taxes_included","money_format"} — cached for an hour.
      def shop_info(shop)
        CodForm::Cache.store.fetch("codf:shop_info:#{shop.id}", expires_in: SHOP_INFO_TTL) do
          data, errors = admin_query(shop, SHOP_QUERY)
          node = data["shop"]
          raise "shop query failed: #{errors.first}" if node.nil?

          {
            "currency" => node["currencyCode"].to_s.presence || shop.currency.to_s,
            "taxes_included" => node["taxesIncluded"] ? true : false,
            "money_format" => node.dig("currencyFormats", "moneyFormat").to_s.presence || shop.money_format.to_s
          }
        end
      rescue StandardError => e
        Rails.logger.warn("[CodForm::CatalogService] shop_info shop_id=#{shop.id} #{e.class}")
        { "currency" => shop.currency.to_s, "taxes_included" => true, "money_format" => shop.money_format.to_s }
      end

      # Runs one Admin GraphQL operation. Returns [data Hash (string keys, camelCase as in the
      # query), Array of top-level error messages]. Raises on transport errors.
      def admin_query(shop, query, variables = {})
        shop.init_session
        client = ShopifyAPI::GraphQL.client
        document = client.parse(query)
        # F.2: a buyer is waiting on every call made from here.
        response = CodFormShopifyTimeout.with { client.query(document, variables: variables) }
        raw = response.respond_to?(:original_hash) ? response.original_hash : nil
        raw = response.to_h if raw.nil? && response.respond_to?(:to_h)
        raw = {} unless raw.is_a?(Hash)
        data = raw["data"].is_a?(Hash) ? raw["data"] : {}
        errors = Array(raw["errors"]).map { |err| err.is_a?(Hash) ? err["message"].to_s : err.to_s }
        [data, errors]
      end

      # Static province / city dataset of a country (lib/cod_form/geo/<CC>.json), or nil.
      # "shopify_provinces" tells whether the province codes are Shopify's own (and can be sent
      # as provinceCode) or ISO 3166-2 codes of a country Shopify has no province list for.
      def geo_dataset(country)
        code = country.to_s.strip.upcase
        return nil unless code.match?(/\A[A-Z]{2}\z/)

        @geo_mutex.synchronize do
          return @geo_cache[code] if @geo_cache.key?(code)

          path = Rails.root.join("lib", "cod_form", "geo", "#{code}.json")
          @geo_cache[code] = File.exist?(path) ? JSON.parse(File.read(path, encoding: "UTF-8")) : nil
        end
      rescue StandardError => e
        Rails.logger.warn("[CodForm::CatalogService] geo dataset #{code} unreadable: #{e.class}")
        nil
      end

      GEO_TTL = 1.hour

      # [{"code","name"}] of a country: the static dataset when there is one, otherwise the
      # existing `provinces` table. [] when the country has no province list (cached 1 h).
      def provinces(country)
        code = country.to_s.strip.upcase
        return [] unless code.match?(/\A[A-Z]{2}\z/)

        dataset = geo_dataset(code)
        return Array(dataset["provinces"]) if dataset

        CodForm::Cache.store.fetch("codf:provinces:#{code}", expires_in: GEO_TTL) do
          Province.where(country_code: code).order(:province_name).pluck(:province_code, :province_name)
                  .reject { |pcode, name| pcode.blank? || name.blank? }
                  .uniq { |pcode, _| pcode }
                  .map { |pcode, name| { "code" => pcode, "name" => name } }
        end
      rescue StandardError => e
        Rails.logger.warn("[CodForm::CatalogService] provinces #{code} unreadable: #{e.class}")
        []
      end

      # Country schema (E.10) with the province mode resolved to "select" | "hidden" for this
      # country (CodForm::Engine::CountrySchema.resolve). This is the schema the session, the geo
      # endpoint and the submit validation all use.
      # The country selector of the form: the enabled countries, or just the buyer's.
      def countries_for(general, country)
        codes = Array(general["countries"]).map { |c| c.to_s.upcase }.select { |c| c.match?(/\A[A-Z]{2}\z/) }
        codes = [country] if codes.empty?
        names = Province.where(country_code: codes).distinct.pluck(:country_code, :country_name).to_h
        codes.map do |code|
          { "code" => code, "name" => names[code].presence || code,
            "dial_code" => CodForm::Engine::CountrySchema.for(country: code)["dial_code"].to_s }
        end
      rescue StandardError
        [{ "code" => country, "name" => country, "dial_code" => CodForm::Engine::CountrySchema.for(country: country)["dial_code"].to_s }]
      end

      def country_schema(country)
        CodForm::Engine::CountrySchema.resolve(
          CodForm::Engine::CountrySchema.for(country: country), has_provinces: provinces(country).any?
        )
      end

      def numeric_id(gid)
        gid.to_s.split("/").last.to_s.split("?").first.to_s
      end

      def to_cents(amount)
        return nil if amount.nil? || amount.to_s.strip.empty?

        (BigDecimal(amount.to_s) * 100).round.to_i
      rescue ArgumentError
        nil
      end

      def sanitize_items(items)
        list = items.is_a?(Array) ? items : []
        raise CodForm::Errors::InvalidItem, "too_many_lines" if list.size > MAX_LINES

        list.map do |item|
          raise CodForm::Errors::InvalidItem, "bad_item" unless item.is_a?(Hash)

          variant_id = (item["variant_id"] || item["id"]).to_s
          quantity = Integer(item["quantity"].to_s, exception: false)
          unless variant_id.match?(/\A\d{1,20}\z/) && quantity && quantity.between?(1, MAX_QUANTITY)
            raise CodForm::Errors::InvalidItem, "bad_item"
          end

          { "variant_id" => variant_id, "quantity" => quantity, "properties" => sanitize_properties(item["properties"]) }
        end
      end

      def sanitize_properties(properties)
        return {} unless properties.is_a?(Hash)

        properties.first(MAX_PROPERTIES).each_with_object({}) do |(key, value), out|
          next if key.to_s.empty? || value.nil? || value.is_a?(Hash) || value.is_a?(Array)

          out[key.to_s[0, 100]] = value.to_s[0, 500]
        end
      end

      private

      def resolve_country(shop, country)
        code = country.to_s.strip.upcase
        code = shop.country_code.to_s.strip.upcase unless code.match?(/\A[A-Z]{2}\z/)
        code.match?(/\A[A-Z]{2}\z/) ? code : "US"
      end

      def variant_cache_key(shop_id, variant_id, country)
        "codf:var:#{shop_id}:#{variant_id}:#{country}"
      end

      def fetch_variants(shop, ids, country)
        return {} if ids.empty?

        gids = ids.map { |id| "gid://shopify/ProductVariant/#{id}" }
        data, errors = admin_query(shop, VARIANTS_QUERY, { ids: gids, country: country })
        if data["nodes"].nil? && errors.any?
          raise CodForm::Errors.build("order_failed") if errors.any? { |m| m.to_s.downcase.include?("throttled") }

          raise "catalog query failed: #{errors.first.to_s[0, 200]}"
        end

        Array(data["nodes"]).each_with_object({}) do |node, out|
          next unless node.is_a?(Hash) && node["__typename"] == "ProductVariant"

          line = build_line(node)
          out[line["variant_id"]] = line
        end
      end

      def build_line(node)
        product = node["product"] || {}
        contextual = node["contextualPricing"] || {}
        price_cents = to_cents(contextual.dig("price", "amount")) || to_cents(node["price"]) || 0
        compare_cents = to_cents(contextual.dig("compareAtPrice", "amount")) || (contextual.empty? ? to_cents(node["compareAtPrice"]) : nil)
        compare_cents = nil if compare_cents && compare_cents <= price_cents
        variant_title = node["title"].to_s
        variant_title = "" if variant_title == "Default Title"

        {
          "variant_id" => numeric_id(node["id"]),
          "product_id" => numeric_id(product["id"]),
          "collection_ids" => Array(product.dig("collections", "nodes")).map { |c| numeric_id(c["id"]) },
          "vendor" => product["vendor"].to_s,
          "title" => product["title"].to_s,
          "variant_title" => variant_title,
          "image" => node.dig("image", "url") || product.dig("featuredImage", "url"),
          "unit_price_cents" => price_cents,
          "compare_at_cents" => compare_cents,
          "currency" => contextual.dig("price", "currencyCode"),
          "grams" => grams(node.dig("inventoryItem", "measurement", "weight")),
          "requires_shipping" => node.dig("inventoryItem", "requiresShipping") != false,
          "taxable" => node["taxable"] != false,
          "gift_card" => product["isGiftCard"] ? true : false,
          "available" => node["availableForSale"] ? true : false,
          # Inventory not tracked: Shopify reports a quantity of 0 (or below) that means nothing,
          # so there is no stock limit at all — availableForSale alone decides.
          "inventory_quantity" => node.dig("inventoryItem", "tracked") == false ? nil : node["inventoryQuantity"],
          "inventory_policy" => node["inventoryPolicy"].to_s.downcase == "continue" ? "continue" : "deny"
        }
      end

      def grams(weight)
        return 0 unless weight.is_a?(Hash)

        (weight["value"].to_f * GRAMS_PER_UNIT.fetch(weight["unit"].to_s, 1.0)).round
      end
    end
  end
end
