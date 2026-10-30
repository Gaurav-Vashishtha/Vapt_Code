# frozen_string_literal: true

module CodForm
  # shops.money_format ("Rs. {{amount}}", "{{amount_no_decimals}} Ft", ...) ->
  # the format hash of CodForm::Engine::Money.format (ARCHITECTURE.md E.1):
  #   {"template"=>"{{amount}} Ft","decimals"=>0,"thousands"=>" ","decimal"=>","}
  #
  # `parse` is pure Ruby (tested standalone); `for` reads the shop.
  class MoneyFormatAdapter
    PLACEHOLDER = /\{\{\s*(amount[a-z_]*)\s*\}\}/.freeze

    # Shopify money-format tokens => [decimals, thousands separator, decimal separator]
    TOKENS = {
      "amount" => [2, ",", "."],
      "amount_no_decimals" => [0, ",", "."],
      "amount_with_comma_separator" => [2, ".", ","],
      "amount_no_decimals_with_comma_separator" => [0, ".", ","],
      "amount_with_apostrophe_separator" => [2, "'", "."],
      "amount_no_decimals_with_space_separator" => [0, " ", ","],
      "amount_with_space_separator" => [2, " ", ","],
      "amount_with_period_and_space_separator" => [2, " ", "."]
    }.freeze

    # Currencies conventionally shown without decimals (E.8).
    ZERO_DECIMAL = %w[HUF COP RSD PKR JPY KRW CLP].freeze

    class << self
      def for(shop, currency: nil, shop_info: nil)
        info = shop_info || CodForm::CatalogService.shop_info(shop)
        shop_currency = info["currency"].to_s.upcase
        currency = currency.to_s.upcase
        return generic(currency) if !currency.empty? && !shop_currency.empty? && currency != shop_currency

        parse(info["money_format"], currency: shop_currency)
      end

      def parse(money_format, currency: nil)
        text = strip_tags(money_format.to_s).strip
        match = text.match(PLACEHOLDER)
        return generic(currency) if match.nil?

        decimals, thousands, decimal = TOKENS.fetch(match[1], TOKENS["amount"])
        {
          "template" => text.sub(PLACEHOLDER, "{{amount}}"),
          "decimals" => decimals,
          "thousands" => thousands,
          "decimal" => decimal
        }
      end

      # Used for a presentment currency that is not the shop currency: "1,234.50 EUR".
      def generic(currency)
        code = currency.to_s.upcase
        {
          "template" => code.empty? ? "{{amount}}" : "{{amount}} #{code}",
          "decimals" => ZERO_DECIMAL.include?(code) ? 0 : 2,
          "thousands" => ",",
          "decimal" => "."
        }
      end

      private

      def strip_tags(text)
        text.gsub(/<[^>]*>/, "")
      end
    end
  end
end
