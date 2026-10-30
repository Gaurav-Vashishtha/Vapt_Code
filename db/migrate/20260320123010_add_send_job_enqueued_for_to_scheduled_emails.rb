# frozen_string_literal: true

class AddSendJobEnqueuedForToScheduledEmails < ActiveRecord::Migration[7.0]
  def change
    add_column :scheduled_emails, :send_job_enqueued_for, :datetime
  end
end

