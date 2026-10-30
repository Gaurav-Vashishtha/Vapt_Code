# frozen_string_literal: true

class AddReportDescriptionsMetricsAndSchedule < ActiveRecord::Migration[7.2]
  def change
    add_column :scheduled_report_definitions, :merchant_description, :text
    add_column :scheduled_report_definitions, :sql_metrics, :jsonb, null: false, default: []

    add_column :scheduled_shop_reports, :schedule_frequency, :string, null: false, default: "daily"
    add_column :scheduled_shop_reports, :weekly_send_wday, :integer
  end
end
