# frozen_string_literal: true

module MerchantWhatsapp
  module CandidateFinder
    module_function

    def shop_ids(rule)
      excluded = ScheduledMerchantWhatsapp.where(merchant_whatsapp_rule_id: rule.id)
                                          .where.not(shop_id: nil).select(:shop_id)
      scope = Shop.includes(:setting).where.not(id: excluded)
      scope = EmailRuleEvaluatorService.apply_date_rule_shop(scope, rule)
      scope = EmailRuleEvaluatorService.apply_conditions_scope_shop(scope, rule)
      scope = restrict_to_test(scope, :shops)
      scope.pluck(:id)
    end

    def uninstalled_ids(rule)
      excluded = ScheduledMerchantWhatsapp.where(merchant_whatsapp_rule_id: rule.id)
                                          .where.not(uninstalled_shop_id: nil).select(:uninstalled_shop_id)
      scope = UninstalledShop.where.not(id: excluded)
      scope = EmailRuleEvaluatorService.apply_date_rule_uninstalled(scope, rule)
      scope = EmailRuleEvaluatorService.apply_conditions_scope_uninstalled(scope, rule)
      scope = restrict_to_test(scope, :uninstalled_shops)
      scope.pluck(:id)
    end

    def restrict_to_test(scope, target)
      return scope unless Config.restricted_to_test_domains?

      column = target == :uninstalled_shops ? :shop_domain : :shopify_domain
      scope.where(column => Config.test_domains)
    end
  end
end
