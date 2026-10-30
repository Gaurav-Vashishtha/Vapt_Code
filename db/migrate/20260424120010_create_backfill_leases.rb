class CreateBackfillLeases < ActiveRecord::Migration[7.0]
  def change
    create_table :backfill_leases do |t|
      t.references :shop_domain, null: false, foreign_key: true
      t.string :lease_key, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end

    # `t.references :shop_domain` already adds an index on `shop_domain_id`.
    add_index :backfill_leases, :lease_key, unique: true
    add_index :backfill_leases, :expires_at
  end
end

