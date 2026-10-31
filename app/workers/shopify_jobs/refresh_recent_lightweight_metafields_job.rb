module ShopifyJobs
  class RefreshRecentLightweightMetafieldsJob
    include Sidekiq::Worker

    # Keep serialized to avoid hammering Partner API / Shopify GraphQL.
    sidekiq_options queue: :scheduled_report_delivery, retry: 1

    # Runs inline (does NOT enqueue ShopifyJobs::RefreshMetafieldLightweightSettingsJob).
    # Criteria: genuine lightweight-settings change detected, but metafields not refreshed after that change.
    def perform
      return if ENV.fetch("SKIP_LIGHTWEIGHT_METAFIELDS_QUEUE", nil) == "true"

      processed = 0
      successes = 0
      failures = 0

      scope = Setting.joins(:shop)
        .where.not(lightweight_settings_changed_at: nil)
        .where(
          "settings.metafield_settings_refreshed_at IS NULL OR settings.metafield_settings_refreshed_at < settings.lightweight_settings_changed_at"
        )

      scope.find_each(batch_size: 500) do |setting|
        processed += 1
        begin
          setting.sync_lightweight_metafields_and_touch_refreshed_at
          successes += 1
        rescue => e
          failures += 1
          Rails.logger.warn("[ShopifyJobs] RefreshRecentLightweightMetafieldsJob failed setting_id=#{setting.id} shop_id=#{setting.shop_id} #{e.class}: #{e.message}")
        end
      end

      Rails.logger.info("[ShopifyJobs] RefreshRecentLightweightMetafieldsJob done processed=#{processed} ok=#{successes} failed=#{failures}")
    end
  end
end

