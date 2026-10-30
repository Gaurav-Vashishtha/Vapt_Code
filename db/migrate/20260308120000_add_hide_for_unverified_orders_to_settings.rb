# frozen_string_literal: true

class AddHideForUnverifiedOrdersToSettings < ActiveRecord::Migration[7.2]
  def up
    add_column :settings, :hide_for_unverified_orders, :boolean, default: false, null: false
    # Existing shops: set to true (current behaviour). New shops get default false.
    execute <<-SQL.squish
      UPDATE settings SET hide_for_unverified_orders = true WHERE id IS NOT NULL
    SQL
  end

  def down
    remove_column :settings, :hide_for_unverified_orders
  end
end
