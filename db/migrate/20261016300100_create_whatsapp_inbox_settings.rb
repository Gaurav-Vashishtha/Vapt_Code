# frozen_string_literal: true

class CreateWhatsappInboxSettings < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_inbox_settings do |t|
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
        t.boolean :read_receipts, null: false, default: true
        t.boolean :auto_label, null: false, default: true
        t.boolean :welcome_enabled, null: false, default: false
        t.text    :welcome_text
        t.boolean :away_enabled, null: false, default: false
        t.text    :away_text
        t.jsonb   :business_hours, null: false, default: {}
        t.jsonb   :keyword_rules, null: false, default: []
        t.boolean :unanswered_email_enabled, null: false, default: false
        t.integer :unanswered_email_minutes, null: false, default: 30
        t.timestamps
      end
    end
  end
end
