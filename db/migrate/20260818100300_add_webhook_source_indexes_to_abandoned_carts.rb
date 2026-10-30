# frozen_string_literal: true

class AddWebhookSourceIndexesToAbandonedCarts < ActiveRecord::Migration[7.2]
  # abandoned_carts is large and hot; a non-concurrent build would hold an
  # ACCESS EXCLUSIVE lock on it for the duration.
  disable_ddl_transaction!

  def change
    add_index :abandoned_carts, %i[shop_id source created_at],
              name: 'idx_abandoned_carts_source_lookup',
              algorithm: :concurrently,
              if_not_exists: true

    # A partial index on is_anchor was originally built here too. On production
    # the concurrent build outlived its connection and the migration died
    # releasing its advisory lock. It is not worth retrying: the index above
    # already serves the anchor lookup, since every anchor query filters on
    # shop_id and source first and anchors are a small slice of each shop's rows.
  end
end
