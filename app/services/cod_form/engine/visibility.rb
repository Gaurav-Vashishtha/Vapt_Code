# frozen_string_literal: true

module CodForm
  module Engine
    # Where the COD button / form may appear (ARCHITECTURE E.4, VIS-1..5).
    class Visibility
      class << self
        # => {"visible"=>bool, "reasons"=>[...], "message"=>String|nil}
        def evaluate(general:, cart:, country:, page:)
          general = general.is_a?(Hash) ? general : {}
          cart = cart.is_a?(Hash) ? cart : {}
          lines = Array(cart["lines"]).select { |line| line.is_a?(Hash) }
          reasons = []
          message = nil

          countries = list(general["countries"]).map(&:upcase)
          reasons << "country_not_enabled" if !countries.empty? && !countries.include?(country.to_s.strip.upcase)

          pages = general["pages"].is_a?(Hash) ? general["pages"] : {}
          reasons << "page_disabled" if !page.nil? && pages.key?(page.to_s) && pages[page.to_s] == false

          products = general["products"].is_a?(Hash) ? general["products"] : {}
          exclude_products = list(products["exclude_product_ids"])
          exclude_collections = list(products["exclude_collection_ids"])
          if lines.any? { |line| matches?(line, exclude_products, exclude_collections) }
            reasons << "product_excluded"
          end
          if products["scope"].to_s == "selected"
            include_products = list(products["include_product_ids"])
            include_collections = list(products["include_collection_ids"])
            unless lines.all? { |line| matches?(line, include_products, include_collections) }
              reasons << "product_not_included"
            end
          end

          order_total = general["order_total"].is_a?(Hash) ? general["order_total"] : {}
          total = cart["total_cents"]
          if total.is_a?(Numeric)
            min = order_total["min_cents"]
            max = order_total["max_cents"]
            if (min.is_a?(Numeric) && total < min) || (max.is_a?(Numeric) && total > max)
              reasons << "order_total_out_of_range"
              text = order_total["message"].to_s.strip
              message = text unless text.empty?
            end
          end

          if general["hide_out_of_stock"] == true && lines.any? { |line| line["available"] == false }
            reasons << "out_of_stock"
          end

          { "visible" => reasons.empty?, "reasons" => reasons, "message" => message }
        end

        private

        def list(value)
          Array(value).map { |item| item.to_s.strip }.reject(&:empty?)
        end

        def matches?(line, product_ids, collection_ids)
          product_ids.include?(line["product_id"].to_s) || (list(line["collection_ids"]) & collection_ids).any?
        end
      end
    end
  end
end
