# frozen_string_literal: true

class IndexOrderConfirmationsOnShopPhoneLast10 < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  # The expression must stay identical to Whatsapp::ContactOrderStats::ORDER_LAST10,
  # otherwise the planner will not match queries to this index.
  def change
    # A killed CONCURRENTLY build leaves an INVALID index that if_not_exists would then skip forever.
    reversible { |dir| dir.up { execute("DROP INDEX CONCURRENTLY IF EXISTS idx_oc_shop_phone_last10") if invalid_index?('idx_oc_shop_phone_last10') } }

    add_index :order_confirmations,
              "shop_id, right(regexp_replace(customer_number, '\\D', '', 'g'), 10), created_at",
              name: 'idx_oc_shop_phone_last10',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
