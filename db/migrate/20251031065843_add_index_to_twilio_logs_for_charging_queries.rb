class AddIndexToTwilioLogsForChargingQueries < ActiveRecord::Migration[7.2]
  def change
    # Optimize queries filtering by shop_id, is_charged, ver_type IN, and status
    # This index covers the common query pattern in DynamicChargeJob and PreviewDynamicChargeJob
    add_index :twilio_logs, [:shop_id, :is_charged, :status, :ver_type],
              name: 'idx_twilio_logs_charging_queries'
  end
end
