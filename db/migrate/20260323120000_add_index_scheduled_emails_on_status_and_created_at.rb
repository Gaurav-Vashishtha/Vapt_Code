# frozen_string_literal: true

class AddIndexScheduledEmailsOnStatusAndCreatedAt < ActiveRecord::Migration[7.2]
  def change
    add_index :scheduled_emails, [:status, :created_at], order: { created_at: :desc }, name: "index_scheduled_emails_on_status_and_created_at_desc"
  end
end
