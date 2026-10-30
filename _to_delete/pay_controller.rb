# frozen_string_literal: true

module Api
  module Form
    # POST /api/form/pay — the storefront "Pay online" button (no form, no session).
    #
    # Answers what the buyer's cart must carry so the existing discount function gives the
    # prepaid discount at Shopify checkout: the cart attributes and discount code of the first
    # matching 100 % prepaid rule that has a discount (Partial payments & COD), exactly what the
    # form's "Pay online instead" hand-off sends for the same rule. No such rule, or anything
    # going wrong: empty attributes, so the buyer simply reaches checkout at full price.
    class PayController < BaseController
      skip_before_action :authenticate_session!

      def create
        render_ok(handoff.merge("checkout_path" => "/checkout"))
      end

      private

      NOTHING = { "cart_attributes" => {}, "discount_code" => nil }.freeze

      def handoff
        country = body["country"].to_s.strip.upcase
        country = shop.country_code.to_s.strip.upcase unless country.match?(/\A[A-Z]{2}\z/)
        lines = CodForm::CatalogService.lines(shop, body["items"], country: country)
        subtotal = lines.sum { |line| line["unit_price_cents"].to_i * line["quantity"].to_i }
        totals = { "subtotal_cents" => subtotal, "line_discount_cents" => 0, "total_cents" => subtotal, "cod_fee_cents" => 0 }

        rule = prepaid_rule(lines, subtotal, totals)
        return NOTHING if rule.nil?

        setting = shop.setting
        result = CodForm::Engine::PartialRules.handoff_attributes(
          rule: rule,
          cart: totals.merge("lines" => lines, "money_format" => CodForm::MoneyFormatAdapter.for(shop, currency: lines.first["currency"])),
          session: { "public_id" => nil, "form_id" => nil, "partial_expand_flow_enabled" => setting&.partial_expand_flow_enabled == true },
          dummy_variant_id: setting&.partial_dummy_variant_id,
          otp_phone_e164: nil,
          country: country
        )
        # There is no form session behind this cart: empty ids and unset values are left out.
        attributes = result["cart_attributes"].except("_codkFormSessionId", "_codkFormId", "_codkSessionId").compact
        { "cart_attributes" => attributes, "discount_code" => result["discount_code"] }
      rescue CodForm::Errors::InvalidItem
        NOTHING
      rescue StandardError => e
        Rails.logger.warn("[Api::Form::Pay] shop_id=#{shop.id} #{e.class}: #{e.message}")
        NOTHING
      end

      # The first rule that applies to this cart, is a 100 % prepaid rule and gives a discount.
      def prepaid_rule(lines, subtotal, totals)
        matched = CodForm::Engine::PartialRules.match(
          rules: CodForm::PartialRulesAdapter.for(shop),
          cart: { "lines" => lines, "total_cents" => subtotal }, address: {}, contact: {}, risk: nil
        )
        matched.find do |rule|
          CodForm::Engine::PartialRules.kind(rule) == "prepaid" &&
            CodForm::Engine::PartialRules.amounts(rule: rule, totals: totals)["discount_cents"].to_i.positive?
        end
      end
    end
  end
end
