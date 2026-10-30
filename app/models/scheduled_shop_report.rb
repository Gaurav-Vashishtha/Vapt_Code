# frozen_string_literal: true

class ScheduledShopReport < ApplicationRecord
  belongs_to :shop
  belongs_to :scheduled_report_definition
  has_many :scheduled_report_deliveries, dependent: :destroy

  delegate :sql_text,
           :name,
           :output_format,
           :builtin?,
           :merchant_description,
           :schedule_frequency,
           to: :scheduled_report_definition

  validates :send_hour, inclusion: { in: 0..23 }
  validates :send_minute, inclusion: { in: 0..59 }
  validate :validate_recipients
  validate :validate_merchant_weekly_day

  before_validation :clear_weekly_wday_when_not_weekly_definition
  before_validation :apply_default_subscribe_opt_out_rules

  scope :enabled, -> { where(enabled: true) }
  # Delivery: opt-in rows use `enabled`; default-on-for-all definitions use absence of explicit_opt_out_at.
  scope :effective_for_delivery, lambda {
    joins(:scheduled_report_definition).where(
      <<~SQL.squish,
        (
          scheduled_report_definitions.default_subscribe_all = TRUE
          AND scheduled_shop_reports.explicit_opt_out_at IS NULL
        )
        OR (
          COALESCE(scheduled_report_definitions.default_subscribe_all, FALSE) = FALSE
          AND scheduled_shop_reports.enabled = TRUE
        )
      SQL
    )
  }

  def report_kind
    scheduled_report_definition.slug
  end

  # Ensures every global report exists for this shop as a subscription row (merchant can opt in).
  # Uses create_or_find_by! so concurrent requests (e.g. React Strict Mode double fetch) cannot
  # hit RecordNotUnique on index_shop_reports_shop_definition_unique.
  def self.sync_subscriptions_for_shop!(shop, retrying: true)
    ScheduledReportDefinition.ordered.find_each do |defn|
      ensure_for_shop_and_definition!(shop, defn)
    end
  rescue ActiveRecord::PreparedStatementCacheExpired
    raise unless retrying

    ActiveRecord::Base.connection_handler.clear_all_connections!
    sync_subscriptions_for_shop!(shop, retrying: false)
  end

  # Idempotent row for one shop + definition (merchant UI and admin backfill).
  def self.ensure_for_shop_and_definition!(shop, defn)
    report = shop.scheduled_shop_reports.create_or_find_by!(
      shop_id: shop.id,
      scheduled_report_definition_id: defn.id,
    ) do |r|
      r.scheduled_report_definition = defn
      assign_defaults_for_new_report!(r, defn)
    end

    if defn.default_subscribe_all?
      report.update_columns(
        enabled: report.explicit_opt_out_at.nil?,
        updated_at: Time.current,
      )
    end

    report
  end

  def self.assign_defaults_for_new_report!(report, defn)
    if defn.default_subscribe_all?
      report.enabled = true
      report.explicit_opt_out_at = nil
      report.send_hour = defn.default_send_hour
      report.send_minute = defn.default_send_minute
      report.weekly_send_wday =
        if defn.schedule_frequency == "weekly"
          defn.default_weekly_send_wday
        end
    else
      report.enabled = false
      report.send_hour = 8
      report.send_minute = 0
      report.weekly_send_wday = defn.schedule_frequency == "weekly" ? 1 : nil
    end
  end

  def deliver_timezone_name
    tz = timezone.to_s.strip
    return tz if tz.present? && ActiveSupport::TimeZone[tz].present?

    self.class.extract_iana_from_shop_timezone(shop.owner_timezone)
  end

  def deliver_timezone
    ActiveSupport::TimeZone[deliver_timezone_name] || ActiveSupport::TimeZone["UTC"]
  end

  def self.extract_iana_from_shop_timezone(tz_string)
    tz_string.to_s.split(")").last.to_s.strip.presence || "UTC"
  rescue StandardError
    "UTC"
  end

  def recipient_list
    raw = recipient_emails.to_s.split(/[,\s]+/).map(&:strip).reject(&:blank?)
    raw << shop.owner_email if raw.empty? && shop.owner_email.present?
    raw.uniq
  end

  def effective_enabled?
    if scheduled_report_definition&.default_subscribe_all?
      explicit_opt_out_at.nil?
    else
      enabled?
    end
  end

  # Tick/drain only enqueue work when local time is at or after today's send slot (no perform_at).
  # Same-day duplicate attempts are skipped via last_sent_on and DeliverReportJob guards.
  def deliver_enqueue_for_tick(now = Time.current)
    return nil unless effective_enabled?

    local = now.in_time_zone(deliver_timezone)
    return nil if last_sent_on == local.to_date

    if schedule_frequency == "weekly"
      return nil if weekly_send_wday.nil?
      return nil unless local.wday == weekly_send_wday
    end

    slot_start = local.beginning_of_day.change(hour: send_hour, min: send_minute, sec: 0)
    :async if local >= slot_start
  end

  def due_for_send?(now = Time.current)
    deliver_enqueue_for_tick(now).present?
  end

  def feature_ready?
    case report_kind
    when "preorder_otp_cart_csv_24h"
      truthy?(shop.setting&.enable_pre_order_otp)
    when "abandoned_cart_messages"
      s = shop.setting
      truthy?(s&.abandoned_cart_enabled) || truthy?(s&.ac_whatsapp)
    else
      true
    end
  end

  # JSON for merchant app / API — never expose admin-authored SQL.
  # schedule_frequency is admin-defined; send time / weekday are merchant-defined.
  def as_merchant_json
    defn = scheduled_report_definition
    slice(
      "id",
      "enabled",
      "recipient_emails",
      "timezone",
      "last_sent_on",
      "send_hour",
      "send_minute",
      "weekly_send_wday",
      "created_at",
      "updated_at",
    ).merge(
      "name" => defn.name,
      "report_kind" => defn.slug,
      "output_format" => defn.output_format,
      "merchant_description" => defn.merchant_description,
      "schedule_frequency" => defn.schedule_frequency,
      "default_subscribe_all" => defn.default_subscribe_all?,
      "enabled" => effective_enabled?,
    )
  end

  private

  def apply_default_subscribe_opt_out_rules
    return unless scheduled_report_definition&.default_subscribe_all?

    if will_save_change_to_enabled?
      self.explicit_opt_out_at = enabled? ? nil : Time.current
    end
    self.enabled = explicit_opt_out_at.nil?
  end

  def truthy?(v)
    v == true || v.to_s == "true"
  end

  def clear_weekly_wday_when_not_weekly_definition
    return if scheduled_report_definition.blank?
    return if scheduled_report_definition.schedule_frequency == "weekly"

    self.weekly_send_wday = nil
  end

  def validate_merchant_weekly_day
    return unless scheduled_report_definition&.schedule_frequency == "weekly"

    if weekly_send_wday.nil? || !weekly_send_wday.in?(0..6)
      errors.add(:weekly_send_wday, "must be Sunday (0) through Saturday (6)")
    end
  end

  def validate_recipients
    return if recipient_emails.blank?

    recipient_list.each do |email|
      unless email.match?(/\A[^@\s]+@[^@\s]+\z/)
        errors.add(:recipient_emails, "contains an invalid address: #{email}")
        break
      end
    end
  end
end
