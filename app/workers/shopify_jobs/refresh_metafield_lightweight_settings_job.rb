# frozen_string_literal: true

module ShopifyJobs
  class RefreshMetafieldLightweightSettingsJob < ActiveJob::Base
    queue_as :scheduled_report_delivery

    def perform(setting_id)
      if ENV['SKIP_LIGHTWEIGHT_METAFIELDS_QUEUE'] == 'true'
        return
      end
      setting = Setting.find_by(id: setting_id)
      return unless setting

      setting.sync_lightweight_metafields_and_touch_refreshed_at
    end
  end
end
