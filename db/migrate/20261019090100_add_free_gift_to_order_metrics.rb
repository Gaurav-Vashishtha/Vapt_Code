# frozen_string_literal: true

class AddFreeGiftToOrderMetrics < ActiveRecord::Migration[7.2]
  def change
    add_column :order_metrics, :free_gift_items, :integer, if_not_exists: true
    add_column :order_metrics, :free_gift_value, :decimal, precision: 12, scale: 2, if_not_exists: true
    add_column :order_metrics, :free_gift_rule_ids, :jsonb, if_not_exists: true
    add_index :order_metrics, [:shop_id, :ordered_at], name: "idx_order_metrics_free_gift", where: "(free_gift_items > 0)", if_not_exists: true
  end
end
