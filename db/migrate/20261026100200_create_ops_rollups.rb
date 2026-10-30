# frozen_string_literal: true

# Small pre-aggregated tables behind the /codk-ops dashboard. The dashboard
# never queries big tables directly.
class CreateOpsRollups < ActiveRecord::Migration[7.2]
  def change
    # One row per IST day x currency x COD/prepaid. Native currency amounts; INR conversion happens at read time.
    create_table :ops_gmv_dailies do |t|
      t.date :stat_date, null: false
      t.string :currency, null: false, default: 'INR'
      t.boolean :is_cod, null: false, default: false
      t.integer :orders, null: false, default: 0
      t.decimal :gmv, precision: 16, scale: 2, null: false, default: 0
      t.integer :unparsed_orders, null: false, default: 0
      t.timestamps
    end
    add_index :ops_gmv_dailies, %i[stat_date currency is_cod], unique: true, name: 'idx_ops_gmv_dailies_key'

    # Written by SubscriptionActiveJob when its sharded run completes.
    create_table :ops_daily_snapshots do |t|
      t.date :stat_date, null: false
      t.integer :active_subscriptions, null: false, default: 0
      t.decimal :mrr_usd, precision: 14, scale: 2, null: false, default: 0
      t.integer :shops_scanned, null: false, default: 0
      t.jsonb :plan_breakdown, null: false, default: {}
      t.boolean :complete, null: false, default: true
      t.timestamps
    end
    add_index :ops_daily_snapshots, :stat_date, unique: true
  end
end
