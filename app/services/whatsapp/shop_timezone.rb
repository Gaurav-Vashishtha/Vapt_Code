# frozen_string_literal: true

module Whatsapp
  # Shopify's owner_timezone looks like "(GMT+05:30) Asia/Kolkata". A blank or
  # unknown zone falls back to UTC explicitly rather than whatever Time.zone is
  # in effect, so schedule and quiet-hours maths stay deterministic.
  module ShopTimezone
    UTC_ZONE = ActiveSupport::TimeZone['UTC']

    module_function

    def for(shop)
      resolve(shop).first
    end

    def managed?(shop)
      resolve(shop).last
    end

    def resolve(shop)
      raw = shop&.owner_timezone.to_s.strip
      return [UTC_ZONE, false] if raw.blank?

      zone = ActiveSupport::TimeZone[ScheduledShopReport.extract_iana_from_shop_timezone(raw)]
      zone ? [zone, true] : [UTC_ZONE, false]
    rescue StandardError
      [UTC_ZONE, false]
    end
  end
end
