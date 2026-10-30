# frozen_string_literal: true

module FreeGifts
  module Catalog
    COLLECTION_PAGE = 250

    VARIANTS_QUERY = <<~GRAPHQL
      query ($ids: [ID!]!) {
        nodes(ids: $ids) {
          ... on ProductVariant {
            id
            title
            price
            availableForSale
            image { url }
            product { id title status featuredMedia { preview { image { url } } } }
          }
        }
      }
    GRAPHQL

    COLLECTION_PRODUCTS_QUERY = <<~GRAPHQL
      query ($id: ID!, $first: Int!) {
        collection(id: $id) { products(first: $first) { nodes { id } } }
      }
    GRAPHQL

    module_function

    def variants(shop, variant_ids)
      ids = Array(variant_ids).compact.uniq
      return {} if ids.empty?

      data, = CodForm::CatalogService.admin_query(shop, VARIANTS_QUERY, { ids: ids.map { |id| "gid://shopify/ProductVariant/#{id}" } })
      Array(data["nodes"]).each_with_object({}) do |node, result|
        next unless node.is_a?(Hash) && node["id"]

        product = node["product"] || {}
        result[FreeGifts.numeric_id(node["id"])] = {
          product_id: FreeGifts.numeric_id(product["id"]),
          product_title: product["title"],
          product_status: product["status"],
          title: node["title"],
          price: node["price"].to_s.to_d,
          available: node["availableForSale"] == true,
          image: node.dig("image", "url") || product.dig("featuredMedia", "preview", "image", "url")
        }
      end
    end

    def collection_product_ids(shop, collection_ids)
      Array(collection_ids).flat_map do |collection_id|
        data, = CodForm::CatalogService.admin_query(
          shop, COLLECTION_PRODUCTS_QUERY, { id: "gid://shopify/Collection/#{collection_id}", first: COLLECTION_PAGE }
        )
        Array(data.dig("collection", "products", "nodes")).filter_map { |node| FreeGifts.numeric_id(node["id"]) }
      end.uniq.first(Config::MAX_COLLECTION_PRODUCTS)
    end

    def hydrate_rules(shop, rules)
      gifts = variants(shop, rules.map { |rule| rule["gift_variant_id"] })
      rules.map do |rule|
        info = gifts[rule["gift_variant_id"]]
        rule = rule.merge("collection_product_ids" => collection_product_ids(shop, rule["collection_ids"])) if rule["trigger"] == "collection"
        next rule unless info

        rule.merge(
          "gift_product_id" => info[:product_id],
          "gift" => {
            "title" => info[:product_title].to_s,
            "variant_title" => info[:title] == "Default Title" ? "" : info[:title].to_s,
            "image" => info[:image],
            "price" => info[:price].to_f
          }
        )
      end
    end
  end
end
