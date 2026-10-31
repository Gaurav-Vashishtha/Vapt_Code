# frozen_string_literal: true

class CreateCustomerSyncTables < ActiveRecord::Migration[7.2]
  def up
    create_table :customer_sync_states do |t|
      t.bigint :shop_id, null: false
      t.bigint :shopify_customer_count, null: false, default: 0
      t.bigint :baseline_count, null: false, default: 0
      t.virtual :unloaded_count, type: :bigint, stored: true,
                                 as: 'GREATEST(shopify_customer_count - baseline_count, 0)'
      t.datetime :count_synced_at
      t.string :status, null: false, default: 'idle'
      t.datetime :last_attempt_at
      t.datetime :last_success_at
      t.datetime :next_attempt_at
      t.integer :consecutive_failures, null: false, default: 0
      t.string :last_error
      t.timestamps
    end
    add_index :customer_sync_states, :shop_id, unique: true
    add_index :customer_sync_states, %i[status unloaded_count]
    add_foreign_key :customer_sync_states, :shops

    create_table :customer_sync_controls do |t|
      t.string :name, null: false, default: 'global'
      t.string :mode, null: false, default: 'running'
      t.string :reason
      t.string :changed_by
      t.datetime :changed_at
      t.datetime :coordinator_heartbeat_at
      t.timestamps
    end
    add_index :customer_sync_controls, :name, unique: true
    execute "INSERT INTO customer_sync_controls (name, mode, created_at, updated_at) VALUES ('global', 'running', now(), now())"

    add_column :customer_bulk_exports, :expected_count, :bigint
    add_column :customer_bulk_exports, :progress_at, :datetime
  end

  def down
    remove_column :customer_bulk_exports, :progress_at
    remove_column :customer_bulk_exports, :expected_count
    drop_table :customer_sync_controls
    drop_table :customer_sync_states
  end
end
