# frozen_string_literal: true

class AddEmailBodyToScheduledReportDefinitions < ActiveRecord::Migration[7.2]
  def change
    add_column :scheduled_report_definitions, :email_body, :text
  end
end
