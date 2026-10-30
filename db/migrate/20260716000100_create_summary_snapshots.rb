class CreateSummarySnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :summary_snapshots do |t|
      t.bigint   :shop_id, null: false
      t.integer  :window_days, null: false, default: 30
      t.jsonb    :payload, default: {}
      t.datetime :computed_at
      t.timestamps
    end

    add_index :summary_snapshots, :shop_id
    add_index :summary_snapshots, %i[shop_id window_days], unique: true
  end
end
