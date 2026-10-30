# frozen_string_literal: true

module Whatsapp
  module Inbox
    module BusinessHours
      WDAY_KEYS = %w[sun mon tue wed thu fri sat].freeze

      module_function

      def open?(setting, time = Time.current, zone: nil)
        hours = setting.business_hours
        return true if hours.blank?

        local = time.in_time_zone(zone || Whatsapp::ShopTimezone.for(setting.shop))
        minute = (local.hour * 60) + local.min
        Array(hours[WDAY_KEYS[local.wday]]).any? do |from, to|
          start = minutes(from)
          finish = minutes(to)
          start && finish && minute >= start && minute < finish
        end
      end

      def closed?(setting, time = Time.current, zone: nil)
        !open?(setting, time, zone: zone)
      end

      def minutes(value)
        return nil unless WhatsappInboxSetting::TIME_FORMAT.match?(value.to_s)

        h, m = value.to_s.split(':').map(&:to_i)
        (h * 60) + m
      end
    end
  end
end
