# frozen_string_literal: true

module MerchantWhatsapp
  module FrequencyGuard
    module_function

    def recent_send?(domain)
      return false if domain.blank?

      MerchantWhatsappLog.recent_send_for_domain(domain, Config.min_gap_hours).present?
    end

    def within_quiet_hours?(record)
      return true unless Config.quiet_hours_enabled?

      tz = record.try(:owner_timezone).presence || ScheduledAt::DEFAULT_TZ
      now = (Time.current.in_time_zone(tz) rescue Time.current)
      now.hour >= Config.quiet_hours_start && now.hour < Config.quiet_hours_end
    end
  end
end
