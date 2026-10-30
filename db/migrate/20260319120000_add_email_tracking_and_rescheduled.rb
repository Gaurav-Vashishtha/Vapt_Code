# frozen_string_literal: true

class AddEmailTrackingAndRescheduled < ActiveRecord::Migration[7.0]
  def change
    add_column :scheduled_emails, :opened_at, :datetime
    add_column :scheduled_emails, :open_tracking_token, :string
    add_index :scheduled_emails, :open_tracking_token, unique: true, where: "open_tracking_token IS NOT NULL"

    # status enum: add "rescheduled" (string column, so we just use a new value)
    # scheduled_emails.status is string; add default for new value in app, existing rows keep pending/sent/etc.
    # No migration needed for enum value - we add rescheduled in the model enum list.

    create_table :email_click_redirects, force: :cascade do |t|
      t.string :token, null: false, index: { unique: true }
      t.references :scheduled_email, null: false, foreign_key: true
      t.text :destination_url, null: false
      t.datetime :clicked_at
      t.timestamps
    end
  end
end
