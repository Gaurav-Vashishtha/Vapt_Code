# frozen_string_literal: true

require "administrate/base_dashboard"

module CodForm
  class PlanLimitDashboard < Administrate::BaseDashboard
    ATTRIBUTE_TYPES = {
      id: Field::Number,
      scope_type: Field::Select.with_options(searchable: false, collection: ::CodForm::PlanLimit::SCOPE_TYPES),
      scope_key: Field::String,
      plan_tier: Field::Select.with_options(searchable: false, include_blank: true,
                                            collection: ::CodForm::PlanLimit::PLAN_TIERS),
      monthly_cap: Field::Number,
      at_cap_behaviour: Field::Select.with_options(searchable: false, include_blank: true,
                                                   collection: ::CodForm::PlanLimit::AT_CAP_BEHAVIOURS),
      grace_orders: Field::Number,
      overage_rate: Field::Number.with_options(decimals: 4),
      active: Field::Boolean,
      note: Field::String,
      created_at: Field::DateTime,
      updated_at: Field::DateTime
    }.freeze

    COLLECTION_ATTRIBUTES = %i[
      id
      scope_type
      scope_key
      plan_tier
      monthly_cap
      at_cap_behaviour
      grace_orders
      overage_rate
      active
    ].freeze

    SHOW_PAGE_ATTRIBUTES = %i[
      id
      scope_type
      scope_key
      plan_tier
      monthly_cap
      at_cap_behaviour
      grace_orders
      overage_rate
      active
      note
      created_at
      updated_at
    ].freeze

    # scope_key: plan tier (free / pro / enterprise / enterprise_plus), country group id, or shop id.
    # monthly_cap blank = unlimited. at_cap_behaviour blank = inherit. overage_rate blank = not billed.
    FORM_ATTRIBUTES = %i[
      scope_type
      scope_key
      plan_tier
      monthly_cap
      at_cap_behaviour
      grace_orders
      overage_rate
      active
      note
    ].freeze

    COLLECTION_FILTERS = {}.freeze

    def display_resource(plan_limit)
      "Plan limit #{plan_limit.scope_type}:#{plan_limit.scope_key}"
    end
  end
end
