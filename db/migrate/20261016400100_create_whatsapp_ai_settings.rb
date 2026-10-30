# frozen_string_literal: true

class CreateWhatsappAiSettings < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_ai_settings do |t|
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
        t.integer  :status, null: false, default: 0
        t.integer  :reply_mode, null: false, default: 0
        t.string   :agent_name
        t.string   :tone, null: false, default: 'friendly'
        t.jsonb    :skills, null: false, default: {}
        t.jsonb    :discount, null: false, default: {}
        t.boolean  :allow_cancel, null: false, default: false
        t.text     :knowledge
        t.text     :handoff_text
        t.jsonb    :test_numbers, null: false, default: []
        t.datetime :went_live_at
        t.timestamps
      end
    end
  end
end
