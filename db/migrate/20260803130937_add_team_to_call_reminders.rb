# frozen_string_literal: true

class AddTeamToCallReminders < ActiveRecord::Migration[7.2]
  def change
    # Which team owns the callback. Existing rows stay NULL and are treated as
    # "support" everywhere in the app (see CallReminder.for_team).
    add_column :call_reminders, :team, :string
    add_index :call_reminders, [:team, :status, :due_on], name: "index_call_reminders_on_team_status_due_on"
  end
end
