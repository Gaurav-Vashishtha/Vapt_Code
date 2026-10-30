# frozen_string_literal: true

module CodForm
  module Engine
    # OFF-2: a product belongs to at most one active quantity offer.
    class OfferOverlap
      ALL = "*"

      class << self
        # => [{"product_id","offer_ids"=>[..]}] among active quantity offers.
        # Offers that target every product conflict with every other active offer (product_id "*").
        def conflicts(offers)
          active = Array(offers).select do |offer|
            offer.is_a?(Hash) && offer["status"].to_s == "active" &&
              (offer["offer_type"].nil? || offer["offer_type"].to_s == "quantity")
          end

          by_product = Hash.new { |hash, key| hash[key] = [] }
          all_scope = []
          active.each do |offer|
            targeting = offer["targeting"].is_a?(Hash) ? offer["targeting"] : {}
            if targeting["scope"].to_s == "selected"
              Array(targeting["product_ids"]).map(&:to_s).reject(&:empty?).uniq.each do |product_id|
                by_product[product_id] << offer["id"]
              end
            else
              all_scope << offer["id"]
            end
          end

          result = []
          if !all_scope.empty? && active.length > 1
            result << { "product_id" => ALL, "offer_ids" => active.map { |offer| offer["id"] } }
          end
          by_product.each do |product_id, ids|
            result << { "product_id" => product_id, "offer_ids" => ids } if ids.length > 1
          end
          result
        end
      end
    end
  end
end
