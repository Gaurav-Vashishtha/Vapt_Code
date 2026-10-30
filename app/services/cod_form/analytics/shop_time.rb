# frozen_string_literal: true

module CodForm
  module Analytics
    # Shop time zone helpers (F28). Stats days and usage periods are in the shop's zone.
    module ShopTime
      ZONE_CACHE_TTL = 1.hour

      module_function

      def zone(shop)
        name = ScheduledShopReport.extract_iana_from_shop_timezone(shop&.owner_timezone)
        ActiveSupport::TimeZone[name.to_s] || ActiveSupport::TimeZone["UTC"]
      rescue StandardError
        ActiveSupport::TimeZone["UTC"]
      end

      # Zone by shop id, cached (used on the hot button-view path).
      def zone_for_id(shop_id)
        name = CodForm::Cache.store.fetch("codf:tz:#{shop_id}", expires_in: ZONE_CACHE_TTL) do
          zone(Shop.find_by(id: shop_id)).name
        end
        ActiveSupport::TimeZone[name.to_s] || ActiveSupport::TimeZone["UTC"]
      rescue StandardError
        ActiveSupport::TimeZone["UTC"]
      end

      def today(shop)
        Time.current.in_time_zone(zone(shop)).to_date
      end

      # UTC time range covering one shop-local day.
      def day_range(zone, date)
        start = zone.local(date.year, date.month, date.day)
        start..(start + 1.day - 0.000001)
      end

      def range(zone, from, to)
        day_range(zone, from).begin..day_range(zone, to).end
      end
    end
  end
end
