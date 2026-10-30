class AddBackfillRetryFieldsToShopDomains < ActiveRecord::Migration[7.0]
  def change
    add_column :shop_domains, :backfill_last_attempt_at, :datetime
    add_column :shop_domains, :backfill_next_retry_at, :datetime
    add_column :shop_domains, :backfill_last_error, :text, default: ""

    add_index :shop_domains, :backfill_last_attempt_at
    add_index :shop_domains, :backfill_next_retry_at
  end
end

