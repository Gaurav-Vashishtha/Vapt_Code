# frozen_string_literal: true

class CreateScheduledEmails < ActiveRecord::Migration[7.0]
  def change
    create_table :scheduled_emails do |t|
      t.references :email_rule, null: false, foreign_key: true
      t.references :shop, null: false, foreign_key: true
      t.string :status, default: "pending", null: false  # pending, sent, skipped, failed
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.text :error_message

      t.timestamps
    end
    add_index :scheduled_emails, [:email_rule_id, :shop_id], unique: true
    add_index :scheduled_emails, :status
  end
end
