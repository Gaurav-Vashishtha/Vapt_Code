# frozen_string_literal: true

# Computes scheduled_at (UTC) for a scheduled email: reference date (e.g. install + N days) at
# rule's scheduled time (hour:minute) in the recipient's timezone. Uses IST (Asia/Kolkata) when
# timezone cannot be determined.
module EmailRuleScheduledAtService
  IST = "Asia/Kolkata"

  module_function

  # @param rule [EmailRule]
  # @param shop [Shop, nil]
  # @param uninstalled_shop [UninstalledShop, nil]
  # @param exclude_scheduled_email_id [Integer, nil] when refreshing an existing record, pass its id so avoid_conflicts skips it
  # @return [Time] UTC time for scheduled_at
  def call(rule, shop:, uninstalled_shop: nil, exclude_scheduled_email_id: nil)
    record = shop || uninstalled_shop
    raise ArgumentError, "Need shop or uninstalled_shop" if record.nil?

    table, column = rule.date_rule_table_and_column
    base_time = resolve_base_time(record, table, column)
    return Time.current if base_time.blank?

    # Hours after reference date: send at base_time + N hours (no time-of-day)
    if rule.date_rule_type == "hours_after_installation"
      scheduled = base_time + rule.date_rule_value.to_i.hours
      return scheduled.utc
    end

    # Days after + optional time of day (existing behavior)
    zone = zone_for_record(record)
    ref_datetime = base_time + rule.date_rule_value.to_i.days
    ref_date = ref_datetime.in_time_zone(zone).to_date

    hour = rule.scheduled_hour
    min  = rule.scheduled_minute

    if hour.nil? && min.nil?
      local_time = zone.local(ref_date.year, ref_date.month, ref_date.day, 0, 0, 0)
      local_time = bump_into_future(local_time, zone)
      local_time = avoid_conflicts(local_time, shop: shop, uninstalled_shop: uninstalled_shop, exclude_id: exclude_scheduled_email_id)
      return local_time.utc
    end

    hour = hour.to_i.clamp(0, 23)
    min  = min.to_i.clamp(0, 59)

    local_time = zone.local(ref_date.year, ref_date.month, ref_date.day, hour, min, 0)
    local_time = bump_into_future(local_time, zone)
    local_time = avoid_conflicts(local_time, shop: shop, uninstalled_shop: uninstalled_shop, exclude_id: exclude_scheduled_email_id)
    local_time.utc
  end

  def zone_for_record(record)
    name = timezone_name_for_record(record)
    ActiveSupport::TimeZone[name].presence || ActiveSupport::TimeZone[IST]
  end

  def timezone_name_for_record(record)
    if record.is_a?(Shop)
      extract_iana_timezone(record.owner_timezone)
    else
      # UninstalledShop has no timezone; use IST
      IST
    end
  end

  def extract_iana_timezone(tz_string)
    return IST if tz_string.blank?
    # e.g. "(GMT+05:30) Asia/Kolkata" or "America/New_York"
    part = tz_string.to_s.split(")").last.to_s.strip
    part.presence || IST
  end

  def resolve_base_time(record, table, column)
    case table
    when "shops"
      record.respond_to?(column) ? record.public_send(column) : nil
    when "settings"
      rec = record.respond_to?(:setting) ? record.setting : nil
      rec&.respond_to?(column) ? rec.public_send(column) : nil
    when "uninstalled_shops"
      record.respond_to?(column) ? record.public_send(column) : nil
    else
      nil
    end
  end

  # Ensure the given local time is strictly in the future relative to now in that same timezone.
  def bump_into_future(local_time, zone)
    now_local = Time.current.in_time_zone(zone)
    while local_time <= now_local
      local_time += 1.day
    end
    local_time
  end

  # If there is already another email scheduled for this recipient on that local date,
  # move to the next day (and repeat). When refreshing an existing record, exclude its id.
  def avoid_conflicts(local_time, shop:, uninstalled_shop:, exclude_id: nil)
    loop do
      start_utc = local_time.beginning_of_day.utc
      end_utc   = local_time.end_of_day.utc
      scope = ScheduledEmail.where("scheduled_at >= ? AND scheduled_at <= ?", start_utc, end_utc)
      scope = scope.where.not(id: exclude_id) if exclude_id.present?
      if shop
        scope = scope.where(shop_id: shop.id)
      elsif uninstalled_shop
        scope = scope.where(uninstalled_shop_id: uninstalled_shop.id)
      end
      break local_time unless scope.exists?
      local_time += 1.day
    end
  end
end
