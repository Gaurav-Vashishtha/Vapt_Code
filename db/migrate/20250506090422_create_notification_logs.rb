class CreateNotificationLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :notification_logs do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :template_name, null: false
      t.datetime :scheduled_at, null: false

      t.timestamps
    end

    add_index :notification_logs, [:shop_id, :template_name, :scheduled_at], unique: true, name: "index_logs_on_shop_template_time"

  end
end
