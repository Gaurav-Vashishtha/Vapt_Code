# frozen_string_literal: true

module CodForm
  module Engine
    # Which form a cart gets (ARCHITECTURE E.13, FRM-22).
    class FormTargeting
      class << self
        # forms = [{"id","is_default","status","position","targeting"=>{"product_ids","collection_ids"}}]
        # requested_id wins only for test sessions (is_test: true).
        # => form hash | nil
        def pick(forms:, cart:, requested_id: nil, is_test: false)
          list = Array(forms).select { |form| form.is_a?(Hash) && active?(form) }
          return nil if list.empty?

          if is_test == true && !requested_id.nil? && !requested_id.to_s.empty?
            requested = list.find { |form| form["id"].to_s == requested_id.to_s }
            return requested if requested
          end

          lines = Array(cart.is_a?(Hash) ? cart["lines"] : nil).select { |line| line.is_a?(Hash) }
          candidates = list.reject { |form| form["is_default"] == true }
                           .each_with_index.sort_by { |form, index| [form["position"].to_i, index] }.map(&:first)
          targeted = candidates.find { |form| lines.any? { |line| targets?(form, line) } }
          targeted || list.find { |form| form["is_default"] == true } || nil
        end

        private

        def active?(form)
          status = form["status"].to_s
          status.empty? || status == "active"
        end

        def targets?(form, line)
          targeting = form["targeting"].is_a?(Hash) ? form["targeting"] : {}
          product_ids = Array(targeting["product_ids"]).map(&:to_s)
          collection_ids = Array(targeting["collection_ids"]).map(&:to_s)
          product_ids.include?(line["product_id"].to_s) || (Array(line["collection_ids"]).map(&:to_s) & collection_ids).any?
        end
      end
    end
  end
end
