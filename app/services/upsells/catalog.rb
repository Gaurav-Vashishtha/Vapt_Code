# frozen_string_literal: true

module Upsells
  module Catalog
    MAX_VARIANTS = 30
    COLLECTION_PRODUCTS = 10

    NODES_QUERY = <<~GRAPHQL
      query ($ids: [ID!]!) {
        nodes(ids: $ids) {
          __typename
          ... on Product {
            id
            title
            handle
            status
            isGiftCard
            totalInventory
            variantsCount { count }
            featuredMedia { preview { image { url } } }
            options { name values }
            variants(first: #{MAX_VARIANTS}) {
              nodes {
                id
                title
                price
                compareAtPrice
                availableForSale
                inventoryQuantity
                media(first: 1) { nodes { preview { image { url } } } }
                selectedOptions { name value }
              }
            }
          }
          ... on Collection {
            id
            title
            productsCount { count }
            image { url }
            products(first: #{COLLECTION_PRODUCTS}, sortKey: COLLECTION_DEFAULT) { nodes { id } }
          }
        }
      }
    GRAPHQL

    module_function

    def nodes(shop, products: [], collections: [])
      gids = products.map { |id| "gid://shopify/Product/#{id}" } + collections.map { |id| "gid://shopify/Collection/#{id}" }
      return { products: {}, collections: {} } if gids.empty?

      data, = CodForm::CatalogService.admin_query(shop, NODES_QUERY, { ids: gids.uniq })
      result = { products: {}, collections: {} }
      Array(data["nodes"]).each do |node|
        next unless node.is_a?(Hash)

        case node["__typename"]
        when "Product" then result[:products][numeric(node["id"])] = product(node)
        when "Collection" then result[:collections][numeric(node["id"])] = collection(node)
        end
      end
      result
    end

    def product(node)
      {
        "id" => numeric(node["id"]),
        "title" => node["title"],
        "handle" => node["handle"],
        "status" => node["status"],
        "gift_card" => node["isGiftCard"] == true,
        "total_inventory" => node["totalInventory"],
        "variants_count" => node.dig("variantsCount", "count"),
        "image" => node.dig("featuredMedia", "preview", "image", "url"),
        "options" => Array(node["options"]).map { |o| { "name" => o["name"], "values" => Array(o["values"]) } },
        "variants" => Array(node.dig("variants", "nodes")).map do |v|
          {
            "id" => numeric(v["id"]),
            "title" => v["title"],
            "price" => v["price"],
            "compare_at_price" => v["compareAtPrice"],
            "available" => v["availableForSale"] == true,
            "inventory_quantity" => v["inventoryQuantity"],
            "image" => v.dig("media", "nodes", 0, "preview", "image", "url"),
            "options" => Array(v["selectedOptions"]).map { |o| o["value"] }
          }
        end
      }
    end

    def collection(node)
      {
        "id" => numeric(node["id"]),
        "title" => node["title"],
        "products_count" => node.dig("productsCount", "count"),
        "image" => node.dig("image", "url"),
        "product_ids" => Array(node.dig("products", "nodes")).map { |p| numeric(p["id"]) }
      }
    end

    def numeric(gid)
      gid.to_s[/(\d+)\z/, 1].to_i
    end
  end
end
