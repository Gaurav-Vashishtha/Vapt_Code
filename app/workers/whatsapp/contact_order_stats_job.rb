module Whatsapp
  class ContactOrderStatsJob < ApplicationJob
    sidekiq_options queue: 'low', retry: 1

    # Hourly cron with overlap so an orders update that lands mid-run is not missed.
    INCREMENTAL_WINDOW = 2.hours

    def perform(mode = 'incremental', shop_id = nil)
      return fan_out(mode) if shop_id.nil?

      shop = Shop.find_by(id: shop_id)
      return unless shop

      since = mode.to_s == 'full' ? nil : INCREMENTAL_WINDOW.ago
      updated = ContactOrderStats.refresh!(shop, since: since)
      Rails.logger.info("[Whatsapp::ContactOrderStatsJob] shop=#{shop.id} mode=#{mode} updated=#{updated}")
    rescue ActiveRecord::QueryCanceled => e
      Rails.logger.warn("[Whatsapp::ContactOrderStatsJob] shop=#{shop_id} mode=#{mode} timed out: #{e.message}")
    end

    private

    def fan_out(mode)
      contact_shop_ids.each { |sid| self.class.perform_async(mode.to_s, sid) }
    end

    # Loose index scan: SELECT DISTINCT shop_id would read every contact row.
    def contact_shop_ids
      ActiveRecord::Base.connection.select_values(<<~SQL.squish).map(&:to_i)
        WITH RECURSIVE s AS (
          SELECT min(shop_id) AS id FROM whatsapp_contacts
          UNION ALL
          SELECT (SELECT min(shop_id) FROM whatsapp_contacts WHERE shop_id > s.id) FROM s WHERE s.id IS NOT NULL
        )
        SELECT id FROM s WHERE id IS NOT NULL
      SQL
    end
  end
end
