# frozen_string_literal: true

class CreateScheduledReportDeliveries < ActiveRecord::Migration[7.2]
  def change
    create_table :scheduled_report_deliveries do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :scheduled_shop_report, null: false, foreign_key: true
      t.references :scheduled_report_definition, null: false, foreign_key: true

      t.string :report_kind, null: false, default: "" # cached slug at send time
      t.boolean :send_now, null: false, default: false
      t.datetime :sent_at

      t.text :recipients
      t.text :subject

      t.string :status, null: false, default: "sent" # sent|failed
      t.text :error_message

      t.timestamps
    end

    add_index :scheduled_report_deliveries, [:sent_at, :report_kind], name: "index_sched_report_deliveries_on_day_and_kind"
    add_index :scheduled_report_deliveries, :status
  end
end

