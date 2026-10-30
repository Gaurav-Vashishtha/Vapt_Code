class AddBillingColumnsToWhatsappMessageLogs < ActiveRecord::Migration[7.2]
  def change
    # Mirror the columns DynamicChargeJob already relies on for TwilioLog:
    # `country_code` so pricing_for can look up the per-country rate,
    # `is_charged` to prevent double-billing, `actual_charge_applied` for audit.
    add_column :whatsapp_message_logs, :country_code, :string, if_not_exists: true
    add_column :whatsapp_message_logs, :is_charged, :boolean, default: false, null: false, if_not_exists: true
    add_column :whatsapp_message_logs, :actual_charge_applied, :decimal, precision: 10, scale: 4, if_not_exists: true

    add_index :whatsapp_message_logs,
              [:shop_id, :is_charged, :status],
              name: 'idx_whatsapp_logs_billing',
              if_not_exists: true
  end
end
