# frozen_string_literal: true

class AddOutcomeToCallReminders < ActiveRecord::Migration[7.2]
  def change
    # The result of the callback attempt, captured when the callback is marked
    # done, so we can report on what happened to scheduled callbacks.
    add_column :call_reminders, :outcome, :string
    add_column :call_reminders, :completed_by, :string
    add_column :call_reminders, :completed_at, :datetime
  end
end
