class AddPrepaidRemindersToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :prepaid_reminders, :jsonb, default: [], null: false
  end
end
