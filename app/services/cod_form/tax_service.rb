# frozen_string_literal: true

module CodForm
  # Tax for a quote, from Shopify, with the very same DraftOrderInput the order will be created
  # with (CodForm::Engine::DraftOrderBuilder), so quote and order agree (ORD-3).
  # Only called for shops whose prices exclude tax, on a complete address (D.2).
  class TaxService
    TTL = 10.minutes
    ATTEMPTS = 2

    MUTATION = <<~GRAPHQL
      mutation ($input: DraftOrderInput!) {
        draftOrderCalculate(input: $input) {
          calculatedDraftOrder {
            totalTaxSet { presentmentMoney { amount currencyCode } }
            totalPriceSet { presentmentMoney { amount currencyCode } }
            taxLines {
              title
              rate
              priceSet { presentmentMoney { amount } }
            }
          }
          userErrors { field message }
        }
      }
    GRAPHQL

    # Keys of the draft input that can change the tax. Contact data never reaches the cache key.
    PRICING_KEYS = %w[lineItems appliedDiscount shippingLine presentmentCurrencyCode taxExempt acceptAutomaticDiscounts].freeze
    ADDRESS_KEYS = %w[countryCode provinceCode zip city].freeze

    class << self
      # => {"amount_cents","lines"=>[{"title","rate","amount_cents"}],"total_cents"} or nil when
      # Shopify could not calculate (the quote then reports tax.status "unavailable").
      def calculate(shop, draft_input)
        input = draft_input.deep_stringify_keys
        key = "codf:tax:#{shop.id}:#{fingerprint(input)}"
        cached = CodForm::Cache.store.read(key)
        return cached if cached.is_a?(Hash)

        result = nil
        ATTEMPTS.times do
          result = attempt(shop, input)
          break if result
        end
        CodForm::Cache.store.write(key, result, expires_in: TTL) if result
        result
      end

      def fingerprint(input)
        address = input["shippingAddress"].is_a?(Hash) ? input["shippingAddress"].slice(*ADDRESS_KEYS) : {}
        Digest::SHA256.hexdigest(JSON.generate([input.slice(*PRICING_KEYS), address]))
      end

      private

      def attempt(shop, input)
        data, errors = CodForm::CatalogService.admin_query(shop, MUTATION, { "input" => input })
        payload = data["draftOrderCalculate"] || {}
        calculated = payload["calculatedDraftOrder"]
        if calculated.nil?
          Rails.logger.warn(
            "[CodForm::TaxService] shop_id=#{shop.id} no result user_errors=#{Array(payload['userErrors']).size} errors=#{errors.size}"
          )
          return nil
        end

        {
          "amount_cents" => CodForm::CatalogService.to_cents(calculated.dig("totalTaxSet", "presentmentMoney", "amount")) || 0,
          "total_cents" => CodForm::CatalogService.to_cents(calculated.dig("totalPriceSet", "presentmentMoney", "amount")),
          "lines" => Array(calculated["taxLines"]).map do |line|
            {
              "title" => line["title"].to_s,
              "rate" => line["rate"].to_f,
              "amount_cents" => CodForm::CatalogService.to_cents(line.dig("priceSet", "presentmentMoney", "amount")) || 0
            }
          end
        }
      rescue StandardError => e
        Rails.logger.warn("[CodForm::TaxService] shop_id=#{shop.id} #{e.class}")
        nil
      end
    end
  end
end
