# frozen_string_literal: true

# Single source of truth for the partial-payment transaction fee (fraction of
# the order amount). Used by the billing page (BillingSnapshotBuilder), the
# monthly charge (DynamicChargeJob) and the charge preview so the merchant
# always sees the rate they are actually billed at.
module PartialTransactionFee
  PRO = 0.008
  ENTERPRISE = 0.005
  ENTERPRISE_PLUS = 0.0
  FREE = 0.015
  # Shops created before this id were onboarded at 1.05% on the Free plan and
  # keep that rate.
  FREE_LEGACY = 0.0105
  LEGACY_SHOP_ID_CUTOFF = 80_600

  module_function

  def default_rate(shop, plan: shop&.plan)
    name = plan&.name.to_s.downcase
    return PRO if name.include?("pro")
    return ENTERPRISE_PLUS if name.include?("enterprise") && name.include?("plus")
    return ENTERPRISE if name.include?("enterprise") || name.include?("premium") || name.include?("india_budget")
    return FREE_LEGACY if shop && shop.id.to_i <= LEGACY_SHOP_ID_CUTOFF

    FREE
  end

  def free_rate(shop)
    shop && shop.id.to_i <= LEGACY_SHOP_ID_CUTOFF ? FREE_LEGACY : FREE
  end

  def custom_rate(setting)
    value = setting&.partial_transaction_fee.to_f
    value.positive? ? value : nil
  end

  def rate_for(shop, plan: shop&.plan, setting: shop&.setting)
    custom_rate(setting) || default_rate(shop, plan: plan)
  end
end
