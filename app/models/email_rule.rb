# frozen_string_literal: true

class EmailRule < ApplicationRecord
  belongs_to :email_template
  has_many :scheduled_emails, dependent: :destroy

  DATE_RULE_TYPES = %w[days_after_installation hours_after_installation].freeze
  TARGETS = %w[shops uninstalled_shops].freeze

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :date_rule_type, presence: true, inclusion: { in: DATE_RULE_TYPES }
  validates :date_rule_value, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :scheduled_hour, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }, allow_nil: true
  validates :scheduled_minute, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 59 }, allow_nil: true
  validate :conditions_format

  # Date/datetime columns for "Reference date field" dropdown (shops/settings for target=shops; uninstalled_shops for target=uninstalled_shops)
  DATE_COLUMNS_FOR_RULE = [
    ["Shops: created_at (installation)", "shops.created_at"],
    ["Shops: updated_at", "shops.updated_at"],
    ["Shops: initial_customer_pull_completed", "shops.initial_customer_pull_completed"],
    ["Shops: partial_rule_sets_metafield_synced_at", "shops.partial_rule_sets_metafield_synced_at"],
    ["Settings: created_at", "settings.created_at"],
    ["Settings: updated_at", "settings.updated_at"],
    ["Settings: metafield_settings_refreshed_at", "settings.metafield_settings_refreshed_at"],
    ["Settings: last_callback_request_at", "settings.last_callback_request_at"],
    ["Settings: last_whatsapp_integration_request_at", "settings.last_whatsapp_integration_request_at"],
    ["Uninstalled shops: created_at", "uninstalled_shops.created_at"],
    ["Uninstalled shops: updated_at", "uninstalled_shops.updated_at"],
  ].freeze

  # Columns for conditions dropdown: all columns from Shop and Setting (sorted)
  SHOP_COLUMNS_FOR_CONDITION = Shop.column_names.sort.freeze

  SETTINGS_COLUMNS_FOR_CONDITION = Setting.column_names.sort.freeze
  UNINSTALLED_SHOP_COLUMNS_FOR_CONDITION = UninstalledShop.column_names.sort.freeze

  # For the form we need [value, label] pairs; build at runtime so column_names are current
  def self.shop_columns_for_condition_options
    SHOP_COLUMNS_FOR_CONDITION.map { |c| [c, c] }
  end

  def self.settings_columns_for_condition_options
    SETTINGS_COLUMNS_FOR_CONDITION.map { |c| [c, c] }
  end

  def self.uninstalled_shop_columns_for_condition_options
    UNINSTALLED_SHOP_COLUMNS_FOR_CONDITION.map { |c| [c, c] }
  end

  scope :active, -> { where(active: true) }

  def conditions_array
    return [] if conditions.blank?
    conditions.is_a?(Array) ? conditions : []
  end

  # Resolve date column for rule (e.g. "shops.created_at" => table and column)
  def date_rule_table_and_column
    col = date_rule_column.presence
    if col.to_s.include?(".")
      parts = col.split(".", 2)
      [parts[0], parts[1]]
    else
      ["shops", "created_at"] # fallback for old rules
    end
  end

  private

  def conditions_format
    return if conditions.blank?
    return errors.add(:conditions, "must be an array") unless conditions.is_a?(Array)
    conditions_array.each_with_index do |c, i|
      next if c.is_a?(Hash) && c["table"].present? && c["column"].present? && c["op"].present?
      errors.add(:conditions, "invalid entry at index #{i}")
    end
  end
end
