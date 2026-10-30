# frozen_string_literal: true

module CodForm
  # cod_form_daily_stats (ARCHITECTURE.md B.17, ANL-5). One row per shop, day (shop time zone),
  # dimension and dimension value. revenue_cents is in shop currency.
  class DailyStat < ApplicationRecord
    self.table_name = "cod_form_daily_stats"

    DIMENSION_ALL = "all"
    DIMENSIONS = %w[all country device product form utm_campaign offer].freeze
    METRIC_KEYS = %w[
      button_views form_opens first_inputs shipping_selected submit_attempts submit_errors orders
      revenue_cents partial_handoffs prepaid_redirects closes otp_sent otp_verified offer_views
      offer_accepts downsell_shown downsell_accepts upsell_views upsell_accepts recovery_opens
      recovered_orders blocked fallbacks
    ].freeze

    belongs_to :shop

    validates :stat_date, presence: true
    validates :dimension, presence: true, inclusion: { in: DIMENSIONS }
    validates :dimension_value, length: { maximum: 255 },
                                uniqueness: { scope: %i[shop_id stat_date dimension] }
    validate :dimension_value_not_nil
    validate :metrics_shape

    scope :between, ->(from, to) { where(stat_date: from..to) }
    scope :for_dimension, ->(dimension) { where(dimension: dimension.to_s) }
    scope :totals, -> { where(dimension: DIMENSION_ALL, dimension_value: "") }

    def metric(key)
      metrics.is_a?(Hash) ? metrics[key.to_s].to_i : 0
    end

    private

    def dimension_value_not_nil
      errors.add(:dimension_value, "can't be nil") if dimension_value.nil?
    end

    def metrics_shape
      errors.add(:metrics, "must be a JSON object") unless metrics.is_a?(Hash)
    end
  end
end
