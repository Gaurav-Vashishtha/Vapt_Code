# frozen_string_literal: true

module Ops
  # Rolls ONE IST day of order_confirmations into ops_gmv_dailies.
  # Test orders are excluded. order_amount is a string column, so only clean
  # numeric values are summed; the rest are counted in unparsed_orders.
  # Idempotent: the day is replaced in a single transaction.
  class GmvRollup
    TZ = 'Asia/Kolkata'
    AMOUNT_RE = '^\s*[0-9]+(\.[0-9]+)?\s*$'
    STATEMENT_TIMEOUT = '120s'

    def self.call(date)
      new(date).call
    end

    INDEX_NAME = 'idx_oc_created_at_brin'

    # The rollup scans order_confirmations by created_at; without the BRIN index that is a full table
    # scan, so callers skip the run until the index exists and is valid.
    def self.index_ready?
      ApplicationRecord.connection.select_value(<<~SQL.squish).present?
        SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = '#{INDEX_NAME}' AND i.indisvalid
      SQL
    end

    def initialize(date)
      @date = date.to_date
    end

    def call
      zone = ActiveSupport::TimeZone[TZ]
      start_t = zone.local(@date.year, @date.month, @date.day).utc
      end_t = start_t + 1.day

      sql = ApplicationRecord.sanitize_sql_array([<<~SQL.squish, start_t, end_t])
        SELECT COALESCE(NULLIF(currency, ''), 'INR') AS cur,
               COALESCE(is_cod_order, false) AS cod,
               COUNT(*) AS orders,
               COALESCE(SUM(CASE WHEN order_amount ~ '#{AMOUNT_RE}' THEN order_amount::numeric END), 0) AS gmv,
               COUNT(*) FILTER (WHERE order_amount IS NULL OR order_amount !~ '#{AMOUNT_RE}') AS unparsed
        FROM order_confirmations
        WHERE created_at >= ? AND created_at < ?
          AND status IS DISTINCT FROM 'Test-Order'
        GROUP BY 1, 2
      SQL

      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SET LOCAL statement_timeout = '#{STATEMENT_TIMEOUT}'")
        rows = ApplicationRecord.connection.select_all(sql).to_a
        OpsGmvDaily.where(stat_date: @date).delete_all
        now = Time.current
        records = rows.map do |r|
          { stat_date: @date, currency: r['cur'].to_s.upcase, is_cod: r['cod'], orders: r['orders'].to_i,
            gmv: r['gmv'], unparsed_orders: r['unparsed'].to_i, created_at: now, updated_at: now }
        end
        OpsGmvDaily.insert_all(records) if records.any?
        records.size
      end
    end
  end
end
