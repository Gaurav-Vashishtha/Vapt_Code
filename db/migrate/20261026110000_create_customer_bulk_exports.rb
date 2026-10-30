# frozen_string_literal: true

# Tracks Shopify Bulk Operation exports of a shop's customers: request -> Shopify builds a
# JSONL file -> copied to our S3 -> loaded into customers/addresses at a throttled pace.
# Small table, no foreign key (avoids locking the hot shops table).
class CreateCustomerBulkExports < ActiveRecord::Migration[7.2]
  def change
    create_table :customer_bulk_exports do |t|
      t.bigint   :shop_id, null: false
      t.string   :shopify_domain, null: false
      t.string   :status, null: false, default: 'requested'
      t.string   :bulk_operation_gid
      t.string   :shopify_status
      t.datetime :since_at
      t.datetime :requested_at, null: false
      t.bigint   :object_count
      t.bigint   :file_size
      t.string   :s3_key
      t.bigint   :s3_bytes
      t.bigint   :rows_loaded, null: false, default: 0
      t.bigint   :rows_failed, null: false, default: 0
      t.integer  :download_attempts, null: false, default: 0
      t.integer  :load_attempts, null: false, default: 0
      t.text     :error
      t.datetime :downloaded_at
      t.datetime :load_started_at
      t.datetime :loaded_at
      t.timestamps
    end

    add_index :customer_bulk_exports, :status
    add_index :customer_bulk_exports, %i[shop_id status]
  end
end
