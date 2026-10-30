# frozen_string_literal: true

module CodForm
  # Feature gates of a shop (ARCHITECTURE.md J.1).
  #
  #   CodForm::Gates.for(shop) # => {"order_bumps" => {"allowed" => true, "min_tier" => "free"}, ...}
  #
  # The storefront never sees a gated-off feature; the admin API answers 402 for it.
  class Gates
    ROWS_CACHE_KEY = "codf:gates:rows"
    ROWS_TTL = 60.seconds

    class << self
      def for(shop, config: nil)
        config ||= CodForm::ShopConfig.for(shop)
        CodForm::Engine::FeatureGates.map(
          tier: Sidekick::PlanCatalog.tier_for(shop),
          gates: rows,
          overrides: config.feature_overrides.is_a?(Hash) ? config.feature_overrides : {}
        )
      end

      def allowed?(shop, feature_key, config: nil)
        gate = self.for(shop, config: config)[feature_key.to_s]
        gate.is_a?(Hash) && gate["allowed"] == true
      end

      # {"feature_key" => true|false} — handy for services that check several gates.
      def flags(shop, config: nil)
        self.for(shop, config: config).transform_values { |gate| gate["allowed"] == true }
      end

      def expire_cache
        CodForm::Cache.store.delete(ROWS_CACHE_KEY)
      end

      private

      def rows
        CodForm::Cache.store.fetch(ROWS_CACHE_KEY, expires_in: ROWS_TTL) do
          CodForm::FeatureGate.all.map(&:to_engine_hash)
        end
      end
    end
  end
end
