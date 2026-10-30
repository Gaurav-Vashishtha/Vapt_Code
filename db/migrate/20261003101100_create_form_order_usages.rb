# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.11): monthly form-order counters per shop (cap accounting).
class CreateFormOrderUsages < ActiveRecord::Migration[7.2]
  def change
    create_table :form_order_usages, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :period, null: false
      t.integer :orders_count, null: false, default: 0
      t.integer :partial_orders_count, null: false, default: 0
      t.integer :test_orders_count, null: false, default: 0
      t.integer :over_cap_count, null: false, default: 0
      t.integer :overage_billed_count, null: false, default: 0
      t.integer :cap_snapshot
      t.datetime :notified_80_at
      t.datetime :notified_100_at
      t.timestamps null: false
    end

    add_index :form_order_usages, %i[shop_id period], unique: true,
              name: "index_form_order_usages_on_shop_id_and_period", if_not_exists: true
  end
end
