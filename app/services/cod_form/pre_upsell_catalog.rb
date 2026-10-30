# frozen_string_literal: true

module CodForm
  # Keeps config["candidates"] of a pre-purchase upsell rule: the products it can offer, each with
  # its sellable variant ids, in the merchant's order (the chosen products) or the collection's own
  # order. Runs when the rule is saved and once a day (CodForm::PreUpsellRefreshJob), so a buyer
  # never waits on a collection lookup; prices and stock are still read live at the session.
  #
  #   CodForm::PreUpsellCatalog.refresh!(offer)   # => true when the list was written
  class PreUpsellCatalog
    MAX_PRODUCTS = 25
    MAX_VARIANTS = CodForm::Engine::PreUpsells::MAX_VARIANTS
    # Pre-purchase upsell rules and bundles keep the same product list.
    TYPES = [CodForm::Engine::PreUpsells::TYPE, CodForm::Engine::Bundles::TYPE].freeze

    PRODUCTS_QUERY = <<~GRAPHQL
      query ($ids: [ID!]!) {
        nodes(ids: $ids) {
          __typename
          ... on Product {
            id
            status
            isGiftCard
            variants(first: #{MAX_VARIANTS}) { nodes { id } }
          }
        }
      }
    GRAPHQL

    COLLECTION_QUERY = <<~GRAPHQL
      query ($id: ID!) {
        collection(id: $id) {
          products(first: #{MAX_PRODUCTS}, sortKey: COLLECTION_DEFAULT) {
            nodes {
              id
              status
              isGiftCard
              variants(first: #{MAX_VARIANTS}) { nodes { id } }
            }
          }
        }
      }
    GRAPHQL

    class << self
      def refresh!(offer)
        return false unless offer.is_a?(CodForm::Offer) && TYPES.include?(offer.offer_type)

        config = offer.config.is_a?(Hash) ? offer.config : {}
        candidates = fetch(offer.shop, config)
        return false if candidates.nil?

        offer.update_columns(
          config: config.merge("candidates" => candidates, "candidates_refreshed_at" => Time.current.utc.iso8601),
          updated_at: Time.current
        )
        true
      rescue StandardError => e
        Rails.logger.warn("[CodForm::PreUpsellCatalog] offer_id=#{offer&.id} #{e.class}: #{e.message.to_s[0, 200]}")
        false
      end

      # [{"product_id","variant_ids"}] or nil when Shopify could not answer (the old list stays).
      def fetch(shop, config)
        if config["source"].to_s == "collection"
          id = config["collection_id"].to_s
          return [] if id.empty?

          data, errors = CodForm::CatalogService.admin_query(shop, COLLECTION_QUERY, { id: "gid://shopify/Collection/#{id}" })
          return nil if data["collection"].nil? && errors.any?

          candidates(Array(data.dig("collection", "products", "nodes")))
        else
          ids = Array(config["product_ids"]).map(&:to_s).reject(&:empty?).first(MAX_PRODUCTS)
          return [] if ids.empty?

          data, errors = CodForm::CatalogService.admin_query(shop, PRODUCTS_QUERY, { ids: ids.map { |pid| "gid://shopify/Product/#{pid}" } })
          return nil if data["nodes"].nil? && errors.any?

          by_id = Array(data["nodes"]).select { |node| node.is_a?(Hash) && node["__typename"] == "Product" }
                                       .index_by { |node| CodForm::CatalogService.numeric_id(node["id"]) }
          candidates(ids.filter_map { |pid| by_id[pid] })
        end
      end

      private

      def candidates(nodes)
        nodes.filter_map do |node|
          next unless node.is_a?(Hash) && node["status"].to_s.upcase == "ACTIVE" && !node["isGiftCard"]

          # Every variant (stock and prices are checked live at the session, so a variant that is
          # back in stock shows again without waiting for the next refresh).
          variant_ids = Array(node.dig("variants", "nodes")).select { |v| v.is_a?(Hash) }
                                                           .map { |v| CodForm::CatalogService.numeric_id(v["id"]) }
          next if variant_ids.empty?

          { "product_id" => CodForm::CatalogService.numeric_id(node["id"]), "variant_ids" => variant_ids }
        end
      end
    end
  end
end
