# frozen_string_literal: true

class MoveReportScheduleToDefinitions < ActiveRecord::Migration[7.2]
  def up
    add_column :scheduled_report_definitions, :schedule_frequency, :string, null: false, default: "daily"
    add_column :scheduled_report_definitions, :weekly_send_wday, :integer
    add_column :scheduled_report_definitions, :send_hour, :integer, null: false, default: 8
    add_column :scheduled_report_definitions, :send_minute, :integer, null: false, default: 0

    if column_exists?(:scheduled_shop_reports, :scheduled_report_definition_id) &&
       column_exists?(:scheduled_shop_reports, :send_hour)
      if column_exists?(:scheduled_shop_reports, :schedule_frequency)
        execute <<~SQL.squish
          UPDATE scheduled_report_definitions AS d
          SET
            send_hour = s.send_hour,
            send_minute = s.send_minute,
            schedule_frequency = s.schedule_frequency,
            weekly_send_wday = s.weekly_send_wday
          FROM (
            SELECT DISTINCT ON (scheduled_report_definition_id)
              scheduled_report_definition_id,
              send_hour,
              send_minute,
              schedule_frequency,
              weekly_send_wday
            FROM scheduled_shop_reports
            ORDER BY scheduled_report_definition_id, id ASC
          ) AS s
          WHERE d.id = s.scheduled_report_definition_id
        SQL
      else
        execute <<~SQL.squish
          UPDATE scheduled_report_definitions AS d
          SET
            send_hour = s.send_hour,
            send_minute = s.send_minute
          FROM (
            SELECT DISTINCT ON (scheduled_report_definition_id)
              scheduled_report_definition_id,
              send_hour,
              send_minute
            FROM scheduled_shop_reports
            ORDER BY scheduled_report_definition_id, id ASC
          ) AS s
          WHERE d.id = s.scheduled_report_definition_id
        SQL
      end
    end

    remove_column :scheduled_shop_reports, :send_hour, :integer if column_exists?(:scheduled_shop_reports, :send_hour)
    remove_column :scheduled_shop_reports, :send_minute, :integer if column_exists?(:scheduled_shop_reports, :send_minute)
    if column_exists?(:scheduled_shop_reports, :schedule_frequency)
      remove_column :scheduled_shop_reports, :schedule_frequency, :string
    end
    if column_exists?(:scheduled_shop_reports, :weekly_send_wday)
      remove_column :scheduled_shop_reports, :weekly_send_wday, :integer
    end
  end

  def down
    add_column :scheduled_shop_reports, :send_hour, :integer, null: false, default: 8 unless column_exists?(:scheduled_shop_reports, :send_hour)
    add_column :scheduled_shop_reports, :send_minute, :integer, null: false, default: 0 unless column_exists?(:scheduled_shop_reports, :send_minute)
    unless column_exists?(:scheduled_shop_reports, :schedule_frequency)
      add_column :scheduled_shop_reports, :schedule_frequency, :string, null: false, default: "daily"
    end
    add_column :scheduled_shop_reports, :weekly_send_wday, :integer unless column_exists?(:scheduled_shop_reports, :weekly_send_wday)

    execute <<~SQL.squish
      UPDATE scheduled_shop_reports AS r
      SET
        send_hour = d.send_hour,
        send_minute = d.send_minute,
        schedule_frequency = d.schedule_frequency,
        weekly_send_wday = d.weekly_send_wday
      FROM scheduled_report_definitions AS d
      WHERE r.scheduled_report_definition_id = d.id
    SQL

    remove_column :scheduled_report_definitions, :schedule_frequency if column_exists?(:scheduled_report_definitions, :schedule_frequency)
    remove_column :scheduled_report_definitions, :weekly_send_wday if column_exists?(:scheduled_report_definitions, :weekly_send_wday)
    remove_column :scheduled_report_definitions, :send_hour if column_exists?(:scheduled_report_definitions, :send_hour)
    remove_column :scheduled_report_definitions, :send_minute if column_exists?(:scheduled_report_definitions, :send_minute)
  end
end
