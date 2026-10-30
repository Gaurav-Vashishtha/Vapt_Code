# frozen_string_literal: true

class AddDefaultSubscribeAllToScheduledReports < ActiveRecord::Migration[7.2]
  def change
    change_table :scheduled_report_definitions, bulk: true do |t|
      t.boolean :default_subscribe_all, null: false, default: false
      t.integer :default_send_hour, null: false, default: 8
      t.integer :default_send_minute, null: false, default: 0
      t.integer :default_weekly_send_wday
    end

    add_column :scheduled_shop_reports, :explicit_opt_out_at, :datetime
  end
end
