# frozen_string_literal: true

class AddIncrementalSyncCursorToShopDomainsAndLastFetchedToRtoOrders < ActiveRecord::Migration[7.0]
  def change
    add_column :shop_domains, :incremental_sync_cursor_at, :datetime
    add_index :shop_domains, :incremental_sync_cursor_at

    add_column :rto_orders, :last_fetched_at, :datetime
    add_index :rto_orders, :last_fetched_at
  end
end
