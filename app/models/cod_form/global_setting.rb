# frozen_string_literal: true

module CodForm
  # cod_form_global_settings (ARCHITECTURE.md B.15). Singleton row.
  class GlobalSetting < ApplicationRecord
    include CodForm::AdminAudited

    self.table_name = "cod_form_global_settings"

    CACHE_KEY = "codf:global"
    CACHE_TTL = 30.seconds
    AT_CAP_BEHAVIOURS = %w[fallback grace flag_only].freeze

    validates :at_cap_behaviour, presence: true, inclusion: { in: AT_CAP_BEHAVIOURS }
    validates :grace_orders, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :singleton_row, on: :create
    validate :usage_notice_thresholds_shape
    validate :settings_shape

    after_commit :expire_cache

    # The singleton, cached for 30 s. The returned record is a persisted copy built from the
    # cached attributes; to change a value, update it and the cache is expired on commit.
    def self.current
      attrs = CodForm::Cache.store.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        order(:id).first_or_create!.attributes
      end
      instantiate(attrs)
    end

    def self.expire_cache
      CodForm::Cache.store.delete(CACHE_KEY)
    end

    # Rate-limit overrides of D.0.4: {"codf/session/ip" => {"limit" => 30, "period" => 60}, ...}
    def rate_limits
      value = settings.is_a?(Hash) ? settings["rate_limits"] : nil
      value.is_a?(Hash) ? value : {}
    end

    private

    def expire_cache
      self.class.expire_cache
    end

    def singleton_row
      errors.add(:base, "only one global settings row is allowed") if self.class.exists?
    end

    def usage_notice_thresholds_shape
      list = usage_notice_thresholds
      valid = list.is_a?(Array) && list.all? { |n| n.is_a?(Integer) && n.between?(1, 100) }
      errors.add(:usage_notice_thresholds, "must be a JSON array of integers between 1 and 100") unless valid
    end

    def settings_shape
      errors.add(:settings, "must be a JSON object") unless settings.is_a?(Hash)
    end
  end
end
