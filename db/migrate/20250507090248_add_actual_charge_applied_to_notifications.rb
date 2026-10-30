class AddActualChargeAppliedToNotifications < ActiveRecord::Migration[7.2]
  def change
    add_column :pre_order_otps, :actual_charge_applied, :decimal, precision: 8, scale: 4, default: 0.0
    add_column :abandoned_carts, :actual_charge_applied, :decimal, precision: 8, scale: 4, default: 0.0
    add_column :twilio_logs, :actual_charge_applied, :decimal, precision: 8, scale: 4, default: 0.0
  end
end