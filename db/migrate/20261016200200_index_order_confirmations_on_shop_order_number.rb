# frozen_string_literal: true

class IndexOrderConfirmationsOnShopOrderNumber < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    # A killed CONCURRENTLY build leaves an INVALID index that if_not_exists would then skip forever.
    reversible { |dir| dir.up { execute("DROP INDEX CONCURRENTLY IF EXISTS idx_oc_shop_order_number") if invalid_index?('idx_oc_shop_order_number') } }

    add_index :order_confirmations, %i[shop_id order_number],
              name: 'idx_oc_shop_order_number',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
