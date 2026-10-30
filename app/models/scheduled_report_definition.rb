# frozen_string_literal: true

class ScheduledReportDefinition < ApplicationRecord
  BUILTIN_SLUGS = %w[
    delivery_status_ratio
    abandoned_cart_messages
    preorder_otp_cart_csv_24h
  ].freeze

  OUTPUT_FORMATS = %w[body_summary csv_attachment].freeze
  SCHEDULE_FREQUENCIES = %w[daily weekly].freeze

  has_many :scheduled_shop_reports, dependent: :destroy
  has_many :shops, through: :scheduled_shop_reports

  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z][a-z0-9_]{0,62}\z/ }
  validates :name, presence: true
  validates :output_format, inclusion: { in: OUTPUT_FORMATS }
  validates :schedule_frequency, inclusion: { in: SCHEDULE_FREQUENCIES }
  validates :default_send_hour, inclusion: { in: 0..23 }
  validates :default_send_minute, inclusion: { in: 0..59 }
  validate :slug_must_not_be_reserved_builtin, on: :create
  validate :validate_nonbuiltin_requires_sql
  validate :validate_sql_syntax_when_present
  validate :validate_sql_metrics
  validate :validate_default_weekly_when_subscribe_all

  before_validation :normalize_builtin_defaults
  before_validation :normalize_sql_metrics_container
  before_validation :clear_default_weekly_when_daily_definition

  after_save :sync_merchant_weekly_fields_on_frequency_change, if: :saved_change_to_schedule_frequency?
  after_save :sync_shop_rows_when_enabling_default_subscribe_for_all

  scope :ordered, -> { order(:slug) }

  def builtin?
    BUILTIN_SLUGS.include?(slug)
  end

  # Merchant / API label: same as legacy + custom slugs (e.g. legacy_custom_12).
  def report_kind
    slug
  end

  # Normalized [{ "metric_name" => "...", "sql" => "..." }, ...]
  def normalized_sql_metrics
    Array(sql_metrics).filter_map do |raw|
      next unless raw.is_a?(Hash)

      name = raw["metric_name"].presence || raw["name"].presence
      sql = raw["sql"].presence || raw["sql_text"].presence
      next if name.blank? || sql.blank?

      { "metric_name" => name.to_s.strip, "sql" => sql.to_s.strip }
    end
  end

  private

  def slug_must_not_be_reserved_builtin
    return unless BUILTIN_SLUGS.include?(slug)

    errors.add(:slug, "is reserved for built-in reports")
  end

  def normalize_builtin_defaults
    return unless builtin? && slug == "preorder_otp_cart_csv_24h"

    self.output_format = "csv_attachment"
  end

  def normalize_sql_metrics_container
    self.sql_metrics = [] if sql_metrics.nil?
  end

  # When admin switches weekly ↔ daily, keep merchant rows consistent (bulk, no callbacks).
  def sync_merchant_weekly_fields_on_frequency_change
    return unless saved_change_to_schedule_frequency?

    if schedule_frequency == "daily"
      scheduled_shop_reports.update_all(weekly_send_wday: nil)
    else
      scheduled_shop_reports.where(weekly_send_wday: nil).update_all(weekly_send_wday: 1)
    end
  end

  def validate_nonbuiltin_requires_sql
    return if builtin?
    return if sql_text.present?
    return if normalized_sql_metrics.any?

    errors.add(:base, "Non built-in reports need either SQL text or at least one metric in SQL metrics")
  end

  def validate_sql_syntax_when_present
    return if sql_text.blank?

    ScheduledReports::SafeSqlValidator.validate!(sql_text)
  rescue ScheduledReports::UnsafeSqlError => e
    errors.add(:sql_text, e.message)
  end

  def validate_sql_metrics
    normalized_sql_metrics.each_with_index do |m, i|
      ScheduledReports::SafeSqlValidator.validate!(m["sql"])
    rescue ScheduledReports::UnsafeSqlError => e
      errors.add(:sql_metrics, "metric #{i + 1} (#{m['metric_name']}): #{e.message}")
    end
  end

  def validate_default_weekly_when_subscribe_all
    return unless default_subscribe_all? && schedule_frequency == "weekly"

    if default_weekly_send_wday.nil? || !default_weekly_send_wday.in?(0..6)
      errors.add(:default_weekly_send_wday, "must be Sunday (0) through Saturday (6) when weekly + default-on for all shops")
    end
  end

  def clear_default_weekly_when_daily_definition
    self.default_weekly_send_wday = nil if schedule_frequency == "daily"
  end

  # Background: create/update a row for every shop (batched). Existing explicit opt-outs stay off.
  def sync_shop_rows_when_enabling_default_subscribe_for_all
    prev = saved_changes["default_subscribe_all"]
    # Enqueue both when toggled on, and when created with the flag already enabled.
    should_enqueue =
      (prev.is_a?(Array) && prev[0] == false && prev[1] == true) ||
      (previously_new_record? && default_subscribe_all?)
    return unless should_enqueue

    ScheduledReports::BackfillDefinitionSubscriptionsJob.perform_async(id)
  end
end
