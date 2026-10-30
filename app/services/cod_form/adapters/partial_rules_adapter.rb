# frozen_string_literal: true

module CodForm
  # Enabled PartialRuleSet rows -> CodForm::Engine::PartialRules rule hashes (ARCHITECTURE.md E.11).
  class PartialRulesAdapter
    # Partial payment is NOT part of the COD Form in this phase: the form offers full COD, and
    # "Pay online" sends the buyer to Shopify checkout without a partial-payment rule. The
    # store's partial payment settings keep working at checkout exactly as before.
    # Set to true to bring the payment step back (next phase).
    ENABLED = false

    class << self
      # [] unless Setting#partial_payment_enabled. Rules come back in position order
      # (PartialRuleSet has a default scope on position).
      def for(shop)
        return [] unless ENABLED

        setting = shop.setting
        return [] unless setting&.partial_payment_enabled

        shop.partial_rule_sets.where(is_enabled: true).map { |rule| rule.as_json.deep_stringify_keys }
      rescue StandardError => e
        Rails.logger.warn("[CodForm::PartialRulesAdapter] shop_id=#{shop.id} #{e.class}")
        []
      end

      def find(shop, rule_id)
        self.for(shop).find { |rule| rule["id"].to_s == rule_id.to_s }
      end
    end
  end
end
