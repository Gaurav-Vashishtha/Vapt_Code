# frozen_string_literal: true

# Bulk files are now read straight from Shopify's file link (no S3 staging), so the S3/download
# columns go away and a byte cursor takes over from the row cursor for resuming a half-loaded file.
class SimplifyCustomerBulkExports < ActiveRecord::Migration[7.2]
  def change
    add_column :customer_bulk_exports, :bytes_loaded, :bigint, null: false, default: 0
    remove_column :customer_bulk_exports, :s3_key, :string
    remove_column :customer_bulk_exports, :s3_bytes, :bigint
    remove_column :customer_bulk_exports, :download_attempts, :integer, null: false, default: 0
    remove_column :customer_bulk_exports, :downloaded_at, :datetime
  end
end
