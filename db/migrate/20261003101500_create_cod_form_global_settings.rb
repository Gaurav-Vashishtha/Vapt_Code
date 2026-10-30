# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.15): singleton row with module-wide switches.
class CreateCodFormGlobalSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_form_global_settings, if_not_exists: true do |t|
      t.boolean :kill_switch, null: false, default: false
      t.boolean :module_default_on, null: false, default: false
      t.string :at_cap_behaviour, null: false, default: "fallback"
      t.integer :grace_orders, null: false, default: 0
      t.boolean :async_orders, null: false, default: false
      t.jsonb :usage_notice_thresholds, null: false, default: [80, 100]
      t.jsonb :settings, null: false, default: {}
      t.timestamps null: false
    end
  end
end
