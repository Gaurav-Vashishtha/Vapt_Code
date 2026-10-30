# frozen_string_literal: true

module CodForm
  # Hand-off of a form session to Shopify checkout: the partial option, a 100 % prepaid rule,
  # or "Pay online" (ARCHITECTURE.md D.8, G.9, PRE-1, PRE-9). The form creates no order here;
  # the existing cart transform / discount / payment functions do what they do today, and
  # CodForm::OrderWebhookHook counts and tags the resulting order.
  class HandoffService
    KINDS = %w[partial prepaid].freeze
    REASONS = %w[buyer_choice blocked preset_a].freeze

    class << self
      # => D.8 response body (string keys). Raises CodForm::Errors::ApiError.
      def call(shop:, config:, session:, params:, ip: nil)
        params = params.is_a?(Hash) ? params : {}
        kind = params["kind"].to_s
        raise CodForm::Errors.build("invalid_request", fields: { "kind" => "error_generic" }) unless KINDS.include?(kind)
        raise CodForm::Errors.build("already_processing") if session.order_id.present? || session.status == CodForm::Session::STATUS_ORDERING

        setting = shop.setting
        built = CodForm::QuoteService.build(shop: shop, config: config, session: session, params: params, stage: "quote", ip: ip)
        quote = built.public_quote
        rule = chosen_rule(shop, quote, params["payment_option_id"], kind)
        raise CodForm::Errors.build("out_of_stock", fields: { "items" => "error_out_of_stock" }) if Array(quote["lines"]).any? { |l| l["available"] == false }

        phone = built.phone
        verified = CodForm::QuoteService.otp_verified_for?(session, phone)
        line_discount = Array(quote["discounts"]).select { |d| %w[quantity_offer downsell].include?(d["kind"]) }.sum { |d| d["amount_cents"].to_i }

        result = CodForm::Engine::PartialRules.handoff_attributes(
          rule: rule,
          cart: {
            "lines" => quote["lines"], "subtotal_cents" => quote["subtotal_cents"], "line_discount_cents" => line_discount,
            "total_cents" => quote["total_cents"], "money_format" => built.money_format
          },
          session: { "public_id" => session.public_id, "form_id" => session.cod_form_id,
                     "partial_expand_flow_enabled" => setting&.partial_expand_flow_enabled == true },
          dummy_variant_id: rule ? dummy_variant_id(shop, setting) : nil,
          otp_phone_e164: verified ? phone["e164"] : nil,
          country: built.address["country"]
        )

        contact = contact_for(params, phone)
        persist(session, kind, rule, contact, built.address, built.contact)
        CodForm::FunnelLogger.log(
          shop_id: shop.id, session_token: session.public_id,
          type: kind == "partial" ? "cf_partial_handoff" : "cf_prepaid_redirect",
          meta: CodForm::QuoteService.funnel_meta(session).merge(
            "reason" => REASONS.include?(params["reason"].to_s) ? params["reason"].to_s : "buyer_choice",
            "value_cents" => quote["total_cents"], "currency" => quote["currency"]
          )
        )

        {
          "ok" => true,
          "kind" => kind,
          "cart_attributes" => result["cart_attributes"],
          "discount_code" => result["discount_code"],
          "buyer_identity" => buyer_identity(contact, built.address),
          "storefront_token" => setting&.store_front_token.to_s.presence,
          "checkout_path" => "/checkout"
        }
      end

      private

      # The rule behind "rule_<id>". It must be one of the options the server itself offered in
      # this quote. A plain prepaid hand-off (Pay online) has no rule.
      def chosen_rule(shop, quote, option_id, kind)
        option_id = option_id.to_s
        if option_id.empty? || option_id == "cod"
          raise CodForm::Errors.build("invalid_request", fields: { "payment_option_id" => "error_generic" }) if kind == "partial"

          return prepaid_discount_rule(shop, quote)
        end

        option = Array(quote.dig("payment_options", "options")).find { |o| o["id"].to_s == option_id }
        unless option && option["rule_id"] && option["kind"].to_s == kind
          raise CodForm::Errors.build("invalid_request", fields: { "payment_option_id" => "error_generic" })
        end

        rule = CodForm::PartialRulesAdapter.find(shop, option["rule_id"])
        raise CodForm::Errors.build("invalid_request", fields: { "payment_option_id" => "error_generic" }) if rule.nil?

        rule
      end

      # PRE-2 (D.8: "when PRE-2 applies, the existing prepaid-discount attribute"): a plain
      # "Pay online" hand-off has no payment option of its own. When the merchant has a matching
      # 100 % prepaid rule that carries a discount (the same rule the payment step would offer as
      # "Pay now and save …"), the buyer who pays online gets that discount: the rule is applied
      # exactly as if the option had been chosen, so the existing discount function sees its
      # usual `_codkDiscounts` entry and discount code. The first such option wins (rule order).
      # No matching rule, or a rule without a discount -> nil (hand-off without a rule, as before).
      def prepaid_discount_rule(shop, quote)
        option = Array(quote.dig("payment_options", "options")).find do |o|
          o.is_a?(Hash) && o["kind"].to_s == "prepaid" && o["rule_id"] && o["discount_cents"].to_i.positive?
        end
        return nil if option.nil?

        CodForm::PartialRulesAdapter.find(shop, option["rule_id"])
      rescue StandardError => e
        Rails.logger.warn("[CodForm::HandoffService] prepaid rule lookup failed shop_id=#{shop.id} #{e.class}")
        nil
      end

      # Same logic as GET /order_confirmations/partial_dummy_variant_id (G.9 step 3).
      def dummy_variant_id(shop, setting)
        return setting.partial_dummy_variant_id if setting&.partial_dummy_variant_id.present?
        return nil unless setting&.partial_payment_enabled

        variant_id = ShopifyServices::PartialDummyVariantCreateService.call(shop)
        setting.update(partial_dummy_variant_id: variant_id) if variant_id.present?
        variant_id
      rescue StandardError => e
        Rails.logger.warn("[CodForm::HandoffService] dummy variant unavailable shop_id=#{shop.id} #{e.class}")
        nil
      end

      def contact_for(params, phone)
        raw = params["contact"].is_a?(Hash) ? params["contact"] : {}
        {
          "first_name" => CodForm::QuoteService.limit(raw["first_name"]),
          "last_name" => CodForm::QuoteService.limit(raw["last_name"]),
          "email" => CodForm::QuoteService.limit(raw["email"]).downcase,
          "phone_e164" => phone["valid"] == true ? phone["e164"].to_s : "",
          "phone_national" => phone["valid"] == true ? phone["national"].to_s : ""
        }
      end

      # Input of the Storefront API cartBuyerIdentityUpdate (G.9 step 5). No placeholder email.
      def buyer_identity(contact, address)
        shopify = CodForm::OrderService.shopify_address(address)
        delivery = {
          "firstName" => contact["first_name"], "lastName" => contact["last_name"],
          "address1" => shopify["address1"], "address2" => shopify["address2"], "city" => shopify["city"],
          "province" => shopify["province"], "country" => shopify["country"], "zip" => shopify["zip"],
          "phone" => contact["phone_e164"]
        }.reject { |key, value| value.to_s.empty? && key != "address2" }
        identity = { "countryCode" => address["country"] }
        identity["email"] = contact["email"] unless contact["email"].empty?
        identity["phone"] = contact["phone_e164"] unless contact["phone_e164"].empty?
        identity["deliveryAddressPreferences"] = [{ "deliveryAddress" => delivery }] unless shopify["address1"].to_s.empty?
        identity
      end

      def persist(session, kind, rule, contact, address, engine_contact)
        session.update_columns(
          status: kind == "partial" ? CodForm::Session::STATUS_HANDOFF_PARTIAL : CodForm::Session::STATUS_HANDOFF_PREPAID,
          partial_rule_set_id: rule ? rule["id"] : nil,
          contact: (session.contact.is_a?(Hash) ? session.contact : {}).merge(contact.reject { |_, v| v.to_s.empty? }),
          address: address,
          phone_normalized: engine_contact["phone_digits"].presence || session.phone_normalized,
          email_normalized: contact["email"].presence || session.email_normalized,
          updated_at: Time.current
        )
      end
    end
  end
end
