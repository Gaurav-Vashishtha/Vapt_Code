# frozen_string_literal: true

# COD Form seed data (ARCHITECTURE.md B.0, J.1, J.2; PM_DECISIONS.md Q8, Q9).
#
# Idempotent: existing rows are never overwritten, so values edited in the internal admin
# survive a re-run. Uses migration-local models (no app code, no callbacks).
class SeedCodFormDefaults < ActiveRecord::Migration[7.2]
  class SeedFeatureGate < ActiveRecord::Base
    self.table_name = "feature_gates"
  end

  class SeedPlanLimit < ActiveRecord::Base
    self.table_name = "plan_limits"
  end

  class SeedCountryGroup < ActiveRecord::Base
    self.table_name = "cod_form_country_groups"
  end

  class SeedGlobalSetting < ActiveRecord::Base
    self.table_name = "cod_form_global_settings"
  end

  # feature_key, min_tier, description (J.1)
  FEATURE_GATES = [
    ["cod_form_core", "free", "Form, buttons, shipping rates, COD fee and COD rules on form orders"],
    ["quantity_offers", "free", "Quantity offers, including the product-page widget"],
    ["block_lists", "free", "Phone / email / IP block lists"],
    ["velocity_limits", "free", "Order limits per phone / email / IP"],
    ["basic_analytics", "free", "Funnel analytics"],
    ["first_pixel", "free", "First pixel per platform"],
    ["abandonment_recovery", "free", "Abandoned form recovery"],
    ["discount_code_field", "free", "Discount code field"],
    ["custom_fields", "free", "Custom form fields"],
    ["preset_a", "free", "Button preset A (Buy now opens the form)"],
    ["templates", "free", "Form templates"],
    ["embedded_mode", "free", "Embedded form"],
    ["order_bumps", "free", "Order bumps"],
    ["downsell", "free", "Downsell on close"],
    ["upsell", "free", "One-click upsell"],
    ["google_sheets", "free", "Google Sheets"],
    ["extra_pixels", "free", "Multiple pixels (max 5 per platform)"],
    ["pixels_p3", "free", "Snapchat, Pinterest, product-specific pixels"],
    ["address_autocomplete", "pro", "Address autocomplete"],
    ["threshold_offers", "pro", "Threshold offers"],
    ["multiple_forms", "pro", "Multiple forms (up to 5)"],
    ["advanced_analytics", "pro", "Advanced analytics"],
    ["klaviyo_omnisend", "pro", "Klaviyo and Omnisend"],
    ["risk_based_otp", "pro", "Risk-based OTP"],
    ["rto_gating", "pro", "RTO gating"],
    ["branding_removal", "pro", "Hide \"Powered by COD King\""],
    ["ab_tests", "enterprise", "Offer A/B tests"]
  ].freeze

  # scope_key, monthly_cap, at_cap_behaviour, grace_orders (J.2). overage_rate is not seeded.
  PLAN_LIMITS = [
    ["free", 60, "grace", 10],
    ["pro", 500, "flag_only", nil],
    ["enterprise", 10_000, "flag_only", nil],
    ["enterprise_plus", nil, nil, nil]
  ].freeze

  LAUNCH_GROUP_NAME = "Launch markets"
  LAUNCH_COUNTRIES = %w[HU CO RS DO MA PE PK].freeze

  def up
    [SeedFeatureGate, SeedPlanLimit, SeedCountryGroup, SeedGlobalSetting].each(&:reset_column_information)
    now = Time.current

    gate_rows = FEATURE_GATES.map do |key, tier, description|
      { feature_key: key, min_tier: tier, enabled: true, description: description,
        created_at: now, updated_at: now }
    end
    SeedFeatureGate.insert_all(gate_rows, unique_by: :index_feature_gates_on_feature_key)

    PLAN_LIMITS.each do |tier, cap, behaviour, grace|
      next if SeedPlanLimit.exists?(scope_type: "plan", scope_key: tier, plan_tier: nil)

      SeedPlanLimit.create!(scope_type: "plan", scope_key: tier, plan_tier: nil, monthly_cap: cap,
                            at_cap_behaviour: behaviour, grace_orders: grace, overage_rate: nil,
                            active: true, note: "seed")
    end

    group = SeedCountryGroup.find_by(name: LAUNCH_GROUP_NAME) ||
            SeedCountryGroup.create!(name: LAUNCH_GROUP_NAME, country_codes: LAUNCH_COUNTRIES,
                                     position: 0, active: true)

    unless SeedPlanLimit.exists?(scope_type: "country_group", scope_key: group.id.to_s, plan_tier: nil)
      SeedPlanLimit.create!(scope_type: "country_group", scope_key: group.id.to_s, plan_tier: nil,
                            monthly_cap: nil, at_cap_behaviour: nil, grace_orders: nil,
                            overage_rate: nil, active: true, note: "seed: launch markets unlimited")
    end

    return if SeedGlobalSetting.exists?

    SeedGlobalSetting.create!(kill_switch: false, module_default_on: false, at_cap_behaviour: "fallback",
                              grace_orders: 0, async_orders: false, usage_notice_thresholds: [80, 100],
                              settings: {})
  end

  def down
    # Seed rows are left in place; the tables are dropped by rolling back their own migrations.
  end
end
