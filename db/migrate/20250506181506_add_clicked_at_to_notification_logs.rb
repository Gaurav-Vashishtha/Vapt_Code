class AddClickedAtToNotificationLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :notification_logs, :clicked_at, :datetime
  end
end
