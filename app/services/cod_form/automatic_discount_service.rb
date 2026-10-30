# frozen_string_literal: true

module CodForm
  # Which of the store's automatic discounts (Buy X get Y, automatic amount / percentage off)
  # apply to a form cart, and how much each line gets.
  #
  # Shopify works it out: draftOrderCalculate with acceptAutomaticDiscounts on the cart's real
  # product lines (with the form's own line discounts on them). Custom lines (COD fee, custom
  # bumps) and shipping are left out of this calculation on purpose, so the answer depends only
  # on the products. The amounts are then put on the order as explicit discounts by
  # CodForm::Engine::Quote / DraftOrderBuilder; the order itself is created with
  # acceptAutomaticDiscounts off, so it totals exactly what the buyer saw.
  class AutomaticDiscountService
    TTL = 10.minutes

    MUTATION = <<~GRAPHQL
      mutation ($input: DraftOrderInput!) {
        draftOrderCalculate(input: $input) {
          calculatedDraftOrder {
            lineItems { discountedTotalSet { presentmentMoney { amount } } }
            platformDiscounts {
              title
              automaticDiscount
              totalAmountPriceSet { presentmentMoney { amount } }
            }
          }
          userErrors { field message }
        }
      }
    GRAPHQL

    class << self
      # quote: CodForm::Engine::Quote.build output computed WITHOUT automatic discounts.
      # => {"amount_cents", "title", "lines" => {line key => cents}, "order_cents"} or nil
      #    (nothing to calculate, or Shopify could not).
      def calculate(shop, quote, country)
        draft = quote.is_a?(Hash) && quote["_draft"].is_a?(Hash) ? quote["_draft"] : {}
        lines = Array(draft["lines"]).select { |line| line.is_a?(Hash) && line["kind"] != "custom_bump" && !line["variant_id"].to_s.empty? }
        return nil if lines.empty?

        input = CodForm::Engine::DraftOrderBuilder.build(
          quote: { "currency" => draft["currency"], "_draft" => { "currency" => draft["currency"], "lines" => lines } },
          contact: {}, address: { "country" => country.to_s }, meta: { "country" => country.to_s }
        ).slice("lineItems", "shippingAddress", "presentmentCurrencyCode").merge("acceptAutomaticDiscounts" => true)

        key = "codf:autodisc:#{shop.id}:#{Digest::SHA256.hexdigest(JSON.generate(input))}"
        cached = CodForm::Cache.store.read(key)
        return cached if cached.is_a?(Hash)

        result = attempt(shop, input, lines)
        CodForm::Cache.store.write(key, result, expires_in: TTL) if result
        result
      rescue StandardError => e
        Rails.logger.warn("[CodForm::AutomaticDiscountService] shop_id=#{shop.id} #{e.class}")
        nil
      end

      private

      def attempt(shop, input, lines)
        data, errors = CodForm::CatalogService.admin_query(shop, MUTATION, { "input" => input })
        payload = data["draftOrderCalculate"] || {}
        calculated = payload["calculatedDraftOrder"]
        if calculated.nil?
          Rails.logger.warn(
            "[CodForm::AutomaticDiscountService] shop_id=#{shop.id} no result user_errors=#{Array(payload['userErrors']).size} errors=#{errors.size}"
          )
          return nil
        end

        automatic = Array(calculated["platformDiscounts"]).select { |d| d.is_a?(Hash) && d["automaticDiscount"] == true }
        total = automatic.sum { |d| cents(d.dig("totalAmountPriceSet", "presentmentMoney", "amount")) }
        per_line = {}
        answered = Array(calculated["lineItems"])
        if total.positive? && answered.size == lines.size
          lines.each_with_index do |line, index|
            ours = (line["unit_price_cents"].to_i - line["unit_discount_cents"].to_i) * line["quantity"].to_i
            shopify = answered[index].is_a?(Hash) ? answered[index].dig("discountedTotalSet", "presentmentMoney", "amount") : nil
            next if shopify.nil?

            off = [[ours - cents(shopify), 0].max, ours].min
            per_line[line["key"].to_s] = off if off.positive?
          end
        end
        # Never hand out more than Shopify's own total; whatever is not on a line is order level.
        allocated = 0
        per_line = per_line.each_with_object({}) do |(line_key, off), out|
          off = [off, total - allocated].min
          next unless off.positive?

          out[line_key] = off
          allocated += off
        end
        Rails.logger.info(
          "[CodForm::AutomaticDiscountService] shop_id=#{shop.id} lines=#{lines.size} discounts=#{automatic.size} " \
          "total_cents=#{total} on_lines_cents=#{allocated}"
        )
        {
          "amount_cents" => total,
          "title" => automatic.map { |d| d["title"].to_s.strip }.reject(&:empty?).uniq.join(", ")[0, 120],
          "lines" => per_line,
          "order_cents" => total - allocated
        }
      end

      def cents(amount)
        CodForm::CatalogService.to_cents(amount).to_i
      end
    end
  end
end
