# frozen_string_literal: true

module CodForm
  # form_order_usages (ARCHITECTURE.md B.11, CAP-1/2). One row per shop and "YYYY-MM" period
  # (shop time zone; the period string is computed by CodForm::CapService.period_for).
  class OrderUsage < ApplicationRecord
    self.table_name = "form_order_usages"

    PERIOD_FORMAT = /\A\d{4}-(0[1-9]|1[0-2])\z/
    COUNTER_COLUMNS = %w[orders_count partial_orders_count test_orders_count over_cap_count overage_billed_count].freeze

    belongs_to :shop

    validates :period, presence: true, format: { with: PERIOD_FORMAT },
                       uniqueness: { scope: :shop_id }
    validates(*COUNTER_COLUMNS.map(&:to_sym), numericality: { only_integer: true, greater_than_or_equal_to: 0 })

    scope :for_period, ->(period) { where(period: period.to_s) }

    # CAP-2: one atomic statement. Creates the row when missing. Returns the new counter value.
    #   CodForm::OrderUsage.increment!(shop_id: 1, period: "2026-10", column: :orders_count)
    def self.increment!(shop_id:, period:, column: :orders_count, by: 1)
      name = column.to_s
      raise ArgumentError, "unknown counter column: #{name}" unless COUNTER_COLUMNS.include?(name)
      raise ArgumentError, "invalid period" unless period.to_s.match?(PERIOD_FORMAT)

      quoted = connection.quote_column_name(name)
      sql = sanitize_sql_array([<<~SQL.squish, { shop_id: Integer(shop_id), period: period.to_s, by: Integer(by) }])
        INSERT INTO form_order_usages (shop_id, period, #{quoted}, created_at, updated_at)
        VALUES (:shop_id, :period, :by, NOW(), NOW())
        ON CONFLICT (shop_id, period)
        DO UPDATE SET #{quoted} = form_order_usages.#{quoted} + :by, updated_at = NOW()
        RETURNING #{quoted}
      SQL
      connection.select_value(sql).to_i
    end

    # The usage row of a shop and period. When no order has been counted yet this is a new,
    # unsaved record with zero counters (reading usage never writes).
    def self.for(shop_id, period)
      find_or_initialize_by(shop_id: shop_id, period: period.to_s)
    end

    def unbilled_over_cap_count
      [over_cap_count.to_i - overage_billed_count.to_i, 0].max
    end
  end
end
