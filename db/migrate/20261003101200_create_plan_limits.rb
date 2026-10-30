# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.12): monthly order caps per plan / country group / shop.
class CreatePlanLimits < ActiveRecord::Migration[7.2]
  def change
    create_table :plan_limits, if_not_exists: true do |t|
      t.string :scope_type, null: false
      t.string :scope_key, null: false
      t.string :plan_tier
      t.integer :monthly_cap
      t.string :at_cap_behaviour
      t.integer :grace_orders
      t.decimal :overage_rate, precision: 10, scale: 4
      t.boolean :active, null: false, default: true
      t.string :note
      t.timestamps null: false
    end

    add_index :plan_limits, %i[scope_type scope_key plan_tier], unique: true,
              name: "index_plan_limits_on_scope_type_and_scope_key_and_plan_tier", if_not_exists: true
  end
end
