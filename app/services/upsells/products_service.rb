# frozen_string_literal: true

module Upsells
  class ProductsService
    MAX_CART_PRODUCTS = 20

    def self.call(shop, cart_product_ids)
      new(shop, cart_product_ids).call
    end

    def initialize(shop, cart_product_ids)
      @shop = shop
      @cart_ids = Array(cart_product_ids).map(&:to_i).select(&:positive?).uniq.first(MAX_CART_PRODUCTS)
      @config = Config.sanitize(shop.additional_setting&.upsell_config)
    end

    def call
      return { products: [], auto_add_variant_ids: [] } unless @config&.dig("enabled")

      max = @config["max_items"]
      variant_filter = {}
      ids = product_ids(variant_filter) - @cart_ids
      auto_ids = auto_add_product_ids - @cart_ids
      hydrated = hydrate((ids.first(max * 2) + auto_ids).uniq, variant_filter).index_by { |p| p["id"] }
      {
        products: ids.filter_map { |id| hydrated[id] }.first(max),
        auto_add_variant_ids: auto_ids.filter_map { |id| hydrated.dig(id, "variants", 0, "id") }
      }
    end

    private

    def auto_add_product_ids
      @config["items"].select { |i| i["type"] == "product" && i["auto_add"] }.map { |i| i["shopify_id"] }
    end

    def product_ids(variant_filter)
      items = @config["items"]
      collection_ids = items.select { |i| i["type"] == "collection" }.map { |i| i["shopify_id"] }
      collections = collection_ids.any? ? Catalog.nodes(@shop, collections: collection_ids)[:collections] : {}

      items.flat_map do |item|
        if item["type"] == "product"
          variant_filter[item["shopify_id"]] = item["variant_ids"] if item["variant_ids"].any?
          [item["shopify_id"]]
        else
          collections.dig(item["shopify_id"], "product_ids") || []
        end
      end.uniq
    end

    def hydrate(ids, variant_filter)
      return [] if ids.empty?

      products = Catalog.nodes(@shop, products: ids)[:products]
      ids.filter_map do |id|
        product = products[id]
        next unless product && product["status"] == "ACTIVE" && !product["gift_card"]

        allowed = variant_filter[id]
        variants = product["variants"].select { |v| v["available"] && (allowed.nil? || allowed.include?(v["id"])) }
        next if variants.empty?

        product.slice("id", "title", "handle", "image", "options").merge("variants" => variants.map { |v| v.except("inventory_quantity") })
      end
    end
  end
end
