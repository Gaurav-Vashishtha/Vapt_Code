# frozen_string_literal: true

class CreateScheduledShopReports < ActiveRecord::Migration[7.2]
  def change
    create_table :scheduled_shop_reports do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :report_kind, null: false
      t.string :name, null: false, default: ""
      t.boolean :enabled, null: false, default: false
      t.string :output_format, null: false, default: "body_summary" # body_summary | csv_attachment
      t.text :recipient_emails, default: "", null: false
      t.integer :send_hour, null: false, default: 8
      t.integer :send_minute, null: false, default: 0
      t.string :timezone, default: "", null: false
      t.text :sql_text
      t.date :last_sent_on
      t.timestamps
    end

    add_index :scheduled_shop_reports, [:shop_id, :report_kind],
              unique: true,
              name: "index_scheduled_shop_reports_shop_builtin_kind",
              where: "report_kind <> 'custom_sql'"
    add_index :scheduled_shop_reports, :enabled
  end
end
