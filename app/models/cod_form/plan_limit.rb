# frozen_string_literal: true

module CodForm
  # plan_limits (ARCHITECTURE.md B.12, J.2). Resolved by CodForm::Engine::CapResolver.
  class PlanLimit < ApplicationRecord
    include CodForm::AdminAudited

    self.table_name = "plan_limits"

    SCOPE_PLAN = "plan"
    SCOPE_COUNTRY_GROUP = "country_group"
    SCOPE_SHOP = "shop"
    SCOPE_TYPES = [SCOPE_PLAN, SCOPE_COUNTRY_GROUP, SCOPE_SHOP].freeze
    PLAN_TIERS = %w[free pro enterprise enterprise_plus].freeze
    AT_CAP_BEHAVIOURS = %w[fallback grace flag_only].freeze

    before_validation :normalize_blanks

    validates :scope_type, presence: true, inclusion: { in: SCOPE_TYPES }
    validates :scope_key, presence: true
    validates :scope_key, inclusion: { in: PLAN_TIERS }, if: -> { scope_type == SCOPE_PLAN }
    validates :scope_key, format: { with: /\A\d+\z/, message: "must be a numeric id" },
                          if: -> { [SCOPE_COUNTRY_GROUP, SCOPE_SHOP].include?(scope_type) }
    validates :plan_tier, inclusion: { in: PLAN_TIERS }, allow_nil: true
    validates :plan_tier, absence: { message: "is only allowed for country_group rows" },
                          unless: -> { scope_type == SCOPE_COUNTRY_GROUP }
    validates :monthly_cap, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :at_cap_behaviour, inclusion: { in: AT_CAP_BEHAVIOURS }, allow_nil: true
    validates :grace_orders, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :overage_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :active, inclusion: { in: [true, false] }
    # The unique index treats NULL plan_tier as distinct, so uniqueness is also checked here.
    validates :scope_key, uniqueness: { scope: %i[scope_type plan_tier], message: "already has a limit for this scope" }

    scope :active, -> { where(active: true) }
    scope :for_scope, ->(type) { where(scope_type: type.to_s) }

    def unlimited?
      monthly_cap.nil?
    end

    # Engine representation for CodForm::Engine::CapResolver (`limits:`), string keys.
    def to_engine_hash
      {
        "id" => id, "scope_type" => scope_type, "scope_key" => scope_key, "plan_tier" => plan_tier,
        "monthly_cap" => monthly_cap, "at_cap_behaviour" => at_cap_behaviour,
        "grace_orders" => grace_orders, "overage_rate" => overage_rate&.to_f, "active" => active
      }
    end

    private

    def normalize_blanks
      self.scope_key = scope_key.to_s.strip if scope_key
      self.plan_tier = plan_tier.presence
      self.at_cap_behaviour = at_cap_behaviour.presence
      self.note = note.presence
    end
  end
end
