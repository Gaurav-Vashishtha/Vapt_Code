# frozen_string_literal: true

module Ops
  # Adds increments to that IST day's row in ops_dynamic_charge_dailies. The job calls it many times
  # per run (run start, each created charge, per-batch counters) so a deploy mid-run loses nothing
  # already written. Atomic increment (several shards run concurrently), and it never raises: a
  # ledger problem must not affect billing.
  class DynamicChargeLedger
    TZ = Ops::GmvRollup::TZ

    def self.record!(runs: 0, amount: 0, charges: 0, failures: 0, capped: 0, below_threshold: 0, sources: {})
      date = Time.current.in_time_zone(TZ).to_date
      values = {
        runs: runs.to_i, charges: charges.to_i, failed_charges: failures.to_i, capped_shops: capped.to_i,
        below_threshold: below_threshold.to_i, amount: amount.to_f.round(2)
      }
      OpsDynamicChargeDaily::SOURCES.each { |source| values[source] = sources[source].to_f.round(2) }

      names = values.keys
      sql = <<~SQL
        INSERT INTO ops_dynamic_charge_dailies (stat_date, #{names.join(', ')}, created_at, updated_at)
        VALUES (:stat_date, #{names.map { |n| ":#{n}" }.join(', ')}, NOW(), NOW())
        ON CONFLICT (stat_date) DO UPDATE SET
          #{names.map { |n| "#{n} = ops_dynamic_charge_dailies.#{n} + EXCLUDED.#{n}" }.join(', ')},
          updated_at = NOW()
      SQL
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array([sql, values.merge(stat_date: date)])
      )
    rescue StandardError => e
      Rails.logger.error("[Ops::DynamicChargeLedger] #{e.class}: #{e.message}")
    end
  end
end
