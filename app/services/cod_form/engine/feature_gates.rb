# frozen_string_literal: true

module CodForm
  module Engine
    # Plan feature gates (ARCHITECTURE E.13 / J.1, CAP-10).
    class FeatureGates
      TIERS = %w[free pro enterprise enterprise_plus].freeze

      class << self
        # gates = [{"feature_key","min_tier","enabled"}]; overrides = {"<feature_key>" => true|false}
        def allowed?(feature_key:, tier:, gates:, overrides:)
          gate = Array(gates).find { |row| row.is_a?(Hash) && row["feature_key"].to_s == feature_key.to_s }
          return false if gate.nil?            # unknown key is denied
          return false if gate["enabled"] == false # off for everyone

          override = overrides.is_a?(Hash) ? overrides[feature_key.to_s] : nil
          return override if override == true || override == false

          rank(tier) >= rank(gate["min_tier"])
        end

        # => {"key" => {"allowed" => bool, "min_tier" => String}}
        def map(tier:, gates:, overrides:)
          Array(gates).each_with_object({}) do |row, out|
            next unless row.is_a?(Hash) && !row["feature_key"].to_s.empty?

            key = row["feature_key"].to_s
            out[key] = {
              "allowed" => allowed?(feature_key: key, tier: tier, gates: gates, overrides: overrides),
              "min_tier" => TIERS.include?(row["min_tier"].to_s) ? row["min_tier"].to_s : "free"
            }
          end
        end

        def rank(tier)
          TIERS.index(tier.to_s) || 0
        end
      end
    end
  end
end
