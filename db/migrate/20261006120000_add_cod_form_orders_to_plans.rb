# frozen_string_literal: true

# COD Form: the monthly form-order limit of a plan lives on the plan itself
# (plans.cod_form_orders; empty = no limit from the plan), and the merchant is told at
# 50 %, 80 % and 100 % of it (form_order_usages.notified_50_at joins the 80 / 100 columns).
class AddCodFormOrdersToPlans < ActiveRecord::Migration[7.2]
  def up
    add_column :plans, :cod_form_orders, :integer unless column_exists?(:plans, :cod_form_orders)
    add_column :form_order_usages, :notified_50_at, :datetime unless column_exists?(:form_order_usages, :notified_50_at)

    change_column_default :cod_form_global_settings, :usage_notice_thresholds, from: [80, 100], to: [50, 80, 100]
    execute <<~SQL.squish
      UPDATE cod_form_global_settings SET usage_notice_thresholds = '[50, 80, 100]'::jsonb
      WHERE usage_notice_thresholds = '[80, 100]'::jsonb
    SQL
  end

  def down
    change_column_default :cod_form_global_settings, :usage_notice_thresholds, from: [50, 80, 100], to: [80, 100]
    remove_column :form_order_usages, :notified_50_at if column_exists?(:form_order_usages, :notified_50_at)
    remove_column :plans, :cod_form_orders if column_exists?(:plans, :cod_form_orders)
  end
end
