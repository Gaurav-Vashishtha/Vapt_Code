# frozen_string_literal: true

module CodForm
  # feature_gates (ARCHITECTURE.md B.14, J.1). Evaluated by CodForm::Engine::FeatureGates.
  class FeatureGate < ApplicationRecord
    include CodForm::AdminAudited

    self.table_name = "feature_gates"

    TIERS = %w[free pro enterprise enterprise_plus].freeze

    validates :feature_key, presence: true, uniqueness: true,
                            format: { with: /\A[a-z0-9_]+\z/, message: "must be snake_case" }
    validates :min_tier, presence: true, inclusion: { in: TIERS }
    validates :enabled, inclusion: { in: [true, false] }

    scope :enabled, -> { where(enabled: true) }

    # Engine representation for CodForm::Engine::FeatureGates (`gates:`), string keys.
    def to_engine_hash
      { "feature_key" => feature_key, "min_tier" => min_tier, "enabled" => enabled }
    end
  end
end
