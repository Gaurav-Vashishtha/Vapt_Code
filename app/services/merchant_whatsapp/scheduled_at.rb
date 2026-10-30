# frozen_string_literal: true

module MerchantWhatsapp
  module ScheduledAt
    module_function

    DEFAULT_TZ = "Asia/Kolkata"

    def for(rule, record)
      base = reference_time(rule, record)
      return Time.current if base.blank?

      offset = rule.date_rule_type == "hours_after_installation" ? rule.date_rule_value.to_i.hours : rule.date_rule_value.to_i.days
      at = base + offset
      return at if rule.scheduled_hour.blank?

      tz = record.try(:owner_timezone).presence || DEFAULT_TZ
      local = (at.in_time_zone(tz) rescue at)
      (local.change(hour: rule.scheduled_hour.to_i, min: rule.scheduled_minute.to_i) rescue at)
    end

    def reference_time(rule, record)
      table, column = rule.date_rule_table_and_column
      source =
        case table
        when "settings" then record.try(:setting)
        else record
        end
      return nil unless source&.respond_to?(column)

      source.public_send(column)
    end
  end
end
