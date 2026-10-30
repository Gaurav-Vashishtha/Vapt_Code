# frozen_string_literal: true

# Global (cross-shop) date-range scans of order_confirmations - used by the
# /codk-ops GMV rollup - had no usable index: every existing index leads with
# shop_id. BRIN is tiny, builds fast and fits append-only, time-ordered rows.
class AddBrinIndexOrderConfirmationsCreatedAt < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    # A killed CONCURRENTLY build leaves an INVALID index that if_not_exists would then skip forever.
    execute("DROP INDEX CONCURRENTLY IF EXISTS idx_oc_created_at_brin") if invalid_index?('idx_oc_created_at_brin')

    add_index :order_confirmations, :created_at,
              using: :brin,
              name: 'idx_oc_created_at_brin',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :order_confirmations, name: 'idx_oc_created_at_brin', algorithm: :concurrently, if_exists: true
  end

  private

  def invalid_index?(name)
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = #{connection.quote(name)} AND NOT i.indisvalid
    SQL
  end
end
