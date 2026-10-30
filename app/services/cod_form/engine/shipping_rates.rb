# frozen_string_literal: true

module CodForm
  module Engine
    # Form shipping rate table (ARCHITECTURE E.5 / C.3, SHP-1..6).
    class ShippingRates
      # No rate fits the cart and address (or the store has no rates at all): shipping is free
      # instead of blocking the order. id 0 is never a stored rate.
      FREE_RATE = { "id" => 0, "name" => "Free shipping", "description" => nil, "price_cents" => 0 }.freeze

      class << self
        # => {"rates"=>[{"id","name","description","price_cents"}], "selected_id"=>Integer|nil,
        #     "price_cents"=>Integer, "none_available"=>bool, "pending_address"=>bool}
        def select(rates:, cart:, address:, subtotal_cents:, currency:, selected_id:, free_shipping:)
          cart = cart.is_a?(Hash) ? cart : {}
          address = address.is_a?(Hash) ? address : {}
          lines = Array(cart["lines"]).select { |line| line.is_a?(Hash) }
          shippable = lines.select { |line| line["requires_shipping"] == true }

          needs_shipping = lines.empty? ? cart["total_quantity"].to_i.positive? : !shippable.empty?
          unless needs_shipping
            return { "rates" => [], "selected_id" => nil, "price_cents" => 0,
                     "none_available" => false, "pending_address" => false }
          end

          quantity = lines.empty? ? cart["total_quantity"].to_i : shippable.sum { |line| line["quantity"].to_i }
          grams = lines.empty? ? cart["total_grams"].to_i : shippable.sum { |line| line["grams"].to_i * line["quantity"].to_i }
          country = address["country"].to_s.strip.upcase
          province = address["province"].to_s.strip.upcase
          province = province.sub(/\A#{Regexp.escape(country)}-/, "") unless country.empty?
          context = { lines: lines, quantity: quantity, grams: grams, subtotal: subtotal_cents.to_i,
                      country: country, province: province }

          pending = false
          qualifying = []
          Array(rates).each do |rate|
            next unless rate.is_a?(Hash)
            next if rate["active"] == false
            next unless currency_ok?(rate["currency"], currency)

            result = qualifies(rate, context)
            pending = true if result == :pending
            qualifying << rate if result == :ok
          end

          sorted = qualifying.each_with_index.sort_by do |rate, index|
            [rate["position"].to_i, rate["price_cents"].to_i, index]
          end.map(&:first)
          free = free_shipping == true
          out = sorted.map do |rate|
            { "id" => rate["id"], "name" => rate["name"].to_s, "description" => rate["description"],
              "price_cents" => free ? 0 : [rate["price_cents"].to_i, 0].max }
          end

          out = [FREE_RATE.dup] if out.empty? && !pending
          chosen = out.find { |rate| !selected_id.nil? && rate["id"].to_s == selected_id.to_s } || out.first
          { "rates" => out,
            "selected_id" => chosen ? chosen["id"] : nil,
            "price_cents" => chosen ? chosen["price_cents"] : 0,
            "none_available" => out.empty?,
            "pending_address" => pending }
        end

        # The rates the browser needs to re-pick shipping by itself when only the address
        # changes (the instant estimate of the storefront form): every rate that passes all the
        # conditions that do NOT depend on the address, already sorted and priced, each with its
        # country / province conditions. nil when the cart needs no shipping.
        # => [{"id","name","description","price_cents","countries"=>[..],"provinces"=>["HU-BU",..]}] | nil
        def for_address_estimate(rates:, cart:, subtotal_cents:, currency:, free_shipping:)
          cart = cart.is_a?(Hash) ? cart : {}
          lines = Array(cart["lines"]).select { |line| line.is_a?(Hash) }
          shippable = lines.select { |line| line["requires_shipping"] == true }
          return nil if shippable.empty?

          context = { lines: lines, quantity: shippable.sum { |line| line["quantity"].to_i },
                      grams: shippable.sum { |line| line["grams"].to_i * line["quantity"].to_i },
                      subtotal: subtotal_cents.to_i, country: "", province: "" }
          qualifying = Array(rates).select do |rate|
            rate.is_a?(Hash) && rate["active"] != false && currency_ok?(rate["currency"], currency) &&
              qualifies(rate.merge("conditions" => without_address(rate["conditions"])), context) == :ok
          end
          sorted = qualifying.each_with_index.sort_by { |rate, index| [rate["position"].to_i, rate["price_cents"].to_i, index] }.map(&:first)
          sorted.map do |rate|
            cond = rate["conditions"].is_a?(Hash) ? rate["conditions"] : {}
            { "id" => rate["id"], "name" => rate["name"].to_s, "description" => rate["description"],
              "price_cents" => free_shipping == true ? 0 : [rate["price_cents"].to_i, 0].max,
              "countries" => strings(cond["countries"]).map(&:upcase), "provinces" => strings(cond["provinces"]).map(&:upcase) }
          end
        end

        private

        def without_address(conditions)
          conditions.is_a?(Hash) ? conditions.reject { |key, _| %w[countries provinces].include?(key.to_s) } : {}
        end

        def currency_ok?(rate_currency, currency)
          text = rate_currency.to_s.strip
          text.empty? || text.casecmp?(currency.to_s.strip)
        end

        # => :ok | :no | :pending (an address condition cannot be evaluated yet)
        def qualifies(rate, ctx)
          cond = rate["conditions"].is_a?(Hash) ? rate["conditions"] : {}
          pending = false

          countries = strings(cond["countries"]).map(&:upcase)
          unless countries.empty?
            if ctx[:country].empty?
              pending = true
            elsif !countries.include?(ctx[:country])
              return :no
            end
          end

          provinces = strings(cond["provinces"]).map(&:upcase)
          unless provinces.empty?
            if ctx[:country].empty? || ctx[:province].empty?
              pending = true
            elsif !provinces.include?("#{ctx[:country]}-#{ctx[:province]}")
              return :no
            end
          end

          return :no unless within?(ctx[:subtotal], cond["subtotal_min_cents"], cond["subtotal_max_cents"])
          return :no unless within?(ctx[:grams], cond["weight_min_grams"], cond["weight_max_grams"])
          return :no unless within?(ctx[:quantity], cond["quantity_min"], cond["quantity_max"])
          return :no unless products_ok?(cond["products"], ctx[:lines])

          pending ? :pending : :ok
        end

        def within?(value, min, max)
          return false if min.is_a?(Numeric) && value < min
          return false if max.is_a?(Numeric) && value > max

          true
        end

        def products_ok?(products, lines)
          return true unless products.is_a?(Hash)

          mode = products["mode"].to_s
          return true unless %w[only exclude].include?(mode)

          product_ids = strings(products["product_ids"])
          collection_ids = strings(products["collection_ids"])
          return true if product_ids.empty? && collection_ids.empty?

          matcher = lambda do |line|
            product_ids.include?(line["product_id"].to_s) || (strings(line["collection_ids"]) & collection_ids).any?
          end
          # custom lines (no product) are neutral for product conditions
          product_lines = lines.reject { |line| line["product_id"].to_s.empty? }
          mode == "only" ? product_lines.all?(&matcher) : product_lines.none?(&matcher)
        end

        def strings(value)
          Array(value).map { |item| item.to_s.strip }.reject(&:empty?)
        end
      end
    end
  end
end
