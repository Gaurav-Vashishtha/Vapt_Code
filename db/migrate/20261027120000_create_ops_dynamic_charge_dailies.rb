# frozen_string_literal: true

# One row per IST day: what DynamicChargeJob created as usage charges (it never stored this itself).
# Written by Ops::DynamicChargeLedger at the end of every run; read by the /codk-ops dashboard.
class CreateOpsDynamicChargeDailies < ActiveRecord::Migration[7.2]
  def change
    create_table :ops_dynamic_charge_dailies do |t|
      t.date    :stat_date, null: false
      t.integer :runs, null: false, default: 0
      t.integer :charges, null: false, default: 0
      t.integer :failed_charges, null: false, default: 0
      t.integer :capped_shops, null: false, default: 0
      t.integer :below_threshold, null: false, default: 0
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0
      %i[sms whatsapp whatsapp_bsp preorder abandoned_sms abandoned_whatsapp ivr prepaid partial_payment].each do |source|
        t.decimal source, precision: 12, scale: 2, null: false, default: 0
      end
      t.timestamps
    end

    add_index :ops_dynamic_charge_dailies, :stat_date, unique: true, name: 'idx_ops_dynamic_charge_dailies_date'
  end
end
