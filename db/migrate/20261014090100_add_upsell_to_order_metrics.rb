# frozen_string_literal: true

class AddUpsellToOrderMetrics < ActiveRecord::Migration[7.2]
  def change
    add_column :order_metrics, :upsell_revenue, :decimal, precision: 12, scale: 2
    add_column :order_metrics, :upsell_items, :integer
    add_index :order_metrics, [:shop_id, :ordered_at], name: "idx_order_metrics_upsell", where: "(upsell_items > 0)"
  end
end
