# frozen_string_literal: true

module CodForm
  # Shopify discount code -> the normalised hash CodForm::Engine::Offers.apply_discount_code
  # expects (ARCHITECTURE.md E.6 / F.1). Only what a draft order can reproduce is supported:
  # DiscountCodeBasic (percentage / fixed amount) and DiscountCodeFreeShipping, for all customers.
  class DiscountCodeService
    TTL = 60.seconds
    MAX_CODE_LENGTH = 64

    MINIMUM_FRAGMENT = <<~GRAPHQL
      minimumRequirement {
        __typename
        ... on DiscountMinimumSubtotal { greaterThanOrEqualToSubtotal { amount currencyCode } }
        ... on DiscountMinimumQuantity { greaterThanOrEqualToQuantity }
      }
    GRAPHQL

    QUERY = <<~GRAPHQL
      query ($code: String!) {
        codeDiscountNodeByCode(code: $code) {
          id
          codeDiscount {
            __typename
            ... on DiscountCodeBasic {
              title
              status
              startsAt
              endsAt
              usageLimit
              asyncUsageCount
              customerSelection { __typename }
              #{MINIMUM_FRAGMENT}
              customerGets {
                value {
                  __typename
                  ... on DiscountPercentage { percentage }
                  ... on DiscountAmount { amount { amount currencyCode } appliesOnEachItem }
                }
                items {
                  __typename
                  ... on AllDiscountItems { allItems }
                  ... on DiscountProducts {
                    products(first: 250) { nodes { id } }
                    productVariants(first: 1) { nodes { id } }
                  }
                  ... on DiscountCollections { collections(first: 250) { nodes { id } } }
                }
              }
            }
            ... on DiscountCodeFreeShipping {
              title
              status
              startsAt
              endsAt
              usageLimit
              asyncUsageCount
              customerSelection { __typename }
              #{MINIMUM_FRAGMENT}
            }
          }
        }
      }
    GRAPHQL

    class << self
      # => {"code","kind","value","applies_to","min_subtotal_cents","min_quantity","currency"}
      #  | {"code","error"=>"not_found"|"inactive"|"usage_limit"|"unsupported"|"unavailable"}
      def lookup(shop, code)
        code = code.to_s.strip
        return { "code" => code, "error" => "not_found" } if code.empty? || code.length > MAX_CODE_LENGTH

        CodForm::Cache.store.fetch("codf:disc:#{shop.id}:#{Digest::SHA256.hexdigest(code.downcase)[0, 24]}", expires_in: TTL) do
          fetch(shop, code)
        end
      rescue StandardError => e
        Rails.logger.warn("[CodForm::DiscountCodeService] shop_id=#{shop.id} #{e.class}")
        { "code" => code, "error" => "unavailable" }
      end

      # Pure mapping of the GraphQL node (string keys) — public for tests.
      def normalize(code, node, now: Time.now)
        discount = node.is_a?(Hash) ? node["codeDiscount"] : nil
        return failure(code, "not_found") unless discount.is_a?(Hash)

        type = discount["__typename"].to_s
        return failure(code, "unsupported") unless %w[DiscountCodeBasic DiscountCodeFreeShipping].include?(type)
        return failure(code, "inactive") unless discount["status"].to_s == "ACTIVE" && within_dates?(discount, now)

        limit = discount["usageLimit"]
        return failure(code, "usage_limit") if limit && discount["asyncUsageCount"].to_i >= limit.to_i
        return failure(code, "unsupported") unless discount.dig("customerSelection", "__typename").to_s == "DiscountCustomerAll"

        base = { "code" => code, "currency" => nil }.merge(minimum(discount["minimumRequirement"]))
        if type == "DiscountCodeFreeShipping"
          return base.merge("kind" => "free_shipping", "value" => 0, "applies_to" => { "all" => true })
        end

        gets = discount["customerGets"] || {}
        applies_to = applies_to(gets["items"])
        return failure(code, "unsupported") if applies_to.nil?

        value = gets["value"] || {}
        case value["__typename"].to_s
        when "DiscountPercentage"
          base.merge("kind" => "percentage", "value" => (value["percentage"].to_f * 100).round(4), "applies_to" => applies_to)
        when "DiscountAmount"
          return failure(code, "unsupported") if value["appliesOnEachItem"]

          cents = CodForm::CatalogService.to_cents(value.dig("amount", "amount"))
          return failure(code, "unsupported") if cents.nil?

          base.merge("kind" => "fixed_amount", "value" => cents, "applies_to" => applies_to,
                     "currency" => value.dig("amount", "currencyCode") || base["currency"])
        else
          failure(code, "unsupported")
        end
      end

      private

      def fetch(shop, code)
        data, errors = CodForm::CatalogService.admin_query(shop, QUERY, { code: code })
        raise "discount query failed" if data.empty? && errors.any?

        normalize(code, data["codeDiscountNodeByCode"], now: Time.current)
      end

      def failure(code, error)
        { "code" => code, "error" => error }
      end

      def within_dates?(discount, now)
        starts = parse_time(discount["startsAt"])
        ends = parse_time(discount["endsAt"])
        (starts.nil? || starts <= now) && (ends.nil? || ends > now)
      end

      def parse_time(value)
        value.to_s.empty? ? nil : Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def minimum(requirement)
        out = { "min_subtotal_cents" => nil, "min_quantity" => nil }
        return out unless requirement.is_a?(Hash)

        case requirement["__typename"].to_s
        when "DiscountMinimumSubtotal"
          money = requirement["greaterThanOrEqualToSubtotal"] || {}
          out["min_subtotal_cents"] = CodForm::CatalogService.to_cents(money["amount"])
          out["currency"] = money["currencyCode"]
        when "DiscountMinimumQuantity"
          out["min_quantity"] = requirement["greaterThanOrEqualToQuantity"].to_i
        end
        out
      end

      def applies_to(items)
        return nil unless items.is_a?(Hash)

        case items["__typename"].to_s
        when "AllDiscountItems"
          { "all" => true }
        when "DiscountProducts"
          return nil if Array(items.dig("productVariants", "nodes")).any?

          { "product_ids" => gids(items.dig("products", "nodes")), "collection_ids" => [] }
        when "DiscountCollections"
          { "product_ids" => [], "collection_ids" => gids(items.dig("collections", "nodes")) }
        end
      end

      def gids(nodes)
        Array(nodes).map { |n| CodForm::CatalogService.numeric_id(n["id"]) }
      end
    end
  end
end
