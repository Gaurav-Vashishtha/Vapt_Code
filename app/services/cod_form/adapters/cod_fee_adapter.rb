# frozen_string_literal: true

module CodForm
  # Setting (COD fees screen) -> CodForm::Engine::CodFee config (ARCHITECTURE.md E.8).
  # This is the only fee source of form orders, on every plan.
  class CodFeeAdapter
    WATCHED_COLUMNS = %w[cod_fee_enabled cod_fees is_percentage cod_label].freeze
    DEFAULT_LABEL = "Cash on delivery fee"
    FX_TTL = 1.hour

    class << self
      # general: cod_form_shop_configs.general (for "cod_fee_taxable").
      def from_setting(setting, currency:, shop_currency:, general: nil)
        value = setting&.cod_fees.to_f
        enabled = setting&.cod_fee_enabled ? true : false
        percentage = setting&.is_percentage ? true : false
        {
          "enabled" => enabled && value.positive?,
          "mode" => percentage ? "percentage" : "fixed",
          "value" => value,
          "label" => setting&.cod_label.to_s.strip.presence || DEFAULT_LABEL,
          "taxable" => general.is_a?(Hash) && general["cod_fee_taxable"] == true,
          "fx_rate" => percentage ? 1.0 : fx_rate(shop_currency, currency),
          "currency" => currency.to_s.upcase
        }
      end

      # Shop currency -> presentment currency. 1.0 when they are the same or when no rate is
      # available (logged; the fixed fee is then charged at face value).
      def fx_rate(from, to)
        from = from.to_s.upcase
        to = to.to_s.upcase
        return 1.0 if from.empty? || to.empty? || from == to

        CodForm::Cache.store.fetch("codf:fx:#{from}:#{to}", expires_in: FX_TTL) do
          bank, _source = ExchangeRateBank.resolve
          rate = bank.get_rate(from, to)
          if rate.nil?
            usd_from = bank.get_rate(from, "USD")
            usd_to = bank.get_rate("USD", to)
            rate = usd_from.to_f * usd_to.to_f if usd_from && usd_to
          end
          raise "no rate" if rate.nil? || rate.to_f <= 0

          rate.to_f
        end
      rescue StandardError => e
        Rails.logger.warn("[CodForm::CodFeeAdapter] fx rate unavailable #{from}->#{to}: #{e.class}")
        1.0
      end
    end
  end
end
