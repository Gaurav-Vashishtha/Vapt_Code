# frozen_string_literal: true

class AddScheduledTimeToEmailRules < ActiveRecord::Migration[7.0]
  def change
    add_column :email_rules, :scheduled_hour, :integer
    add_column :email_rules, :scheduled_minute, :integer
  end
end
