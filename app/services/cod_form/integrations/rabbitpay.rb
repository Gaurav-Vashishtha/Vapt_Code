# frozen_string_literal: true

module CodForm
  module Integrations
    # RabbitPay hand-off (PRE-6): INTERFACE ONLY. There is no RabbitPay code in this release.
    #
    # The contract a pay-online handler builds on:
    #   - cod_form_integrations row, provider "rabbitpay", config {"enabled" => bool}
    #   - the session response carries features.pay_online_handler = handler_expected?(shop), so
    #     the form waits for a handler registered with window.CODKing.registerPayOnlineHandler(fn)
    #     (or a cancelled `codking:pay_online` event) before redirecting to Shopify checkout
    #   - the handler receives the payload of ARCHITECTURE.md G.4; `handoff_payload` documents
    #     the same shape server side for a future server-to-server hand-off
    module Rabbitpay
      PROVIDER = "rabbitpay"

      module_function

      def handler_expected?(shop)
        row = CodForm::Integration.find_by(shop_id: shop.id, provider: PROVIDER)
        !row.nil? && row.config.is_a?(Hash) && row.config["enabled"] == true
      rescue StandardError
        false
      end

      # G.4 payload: {session_id, shop, currency, total_cents, items, contact, address, discounts, return_url}
      def handoff_payload(session, shop:, return_url: nil)
        quote = session.quote_snapshot.is_a?(Hash) ? session.quote_snapshot : {}
        {
          "session_id" => session.public_id,
          "shop" => shop.shopify_domain,
          "currency" => session.currency || quote["currency"],
          "total_cents" => quote["total_cents"].to_i,
          "items" => Array(quote["lines"]).filter_map do |line|
            next unless line.is_a?(Hash)

            { "variant_id" => line["variant_id"].to_s, "quantity" => line["quantity"].to_i,
              "price_cents" => line["unit_price_cents"].to_i }
          end,
          "contact" => session.contact.is_a?(Hash) ? session.contact : {},
          "address" => session.address.is_a?(Hash) ? session.address : {},
          "discounts" => Array(quote["discounts"]),
          "return_url" => return_url
        }
      end
    end
  end
end
