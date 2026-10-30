# frozen_string_literal: true

class CreateWhatsappAiRuns < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_ai_runs do |t|
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.bigint   :whatsapp_conversation_id
        t.bigint   :trigger_message_id
        t.bigint   :reply_message_id
        t.string   :mode, null: false
        t.string   :outcome, null: false
        t.string   :intent
        t.text     :reply_text
        t.string   :handoff_reason
        t.jsonb    :actions, null: false, default: []
        t.integer  :credits_charged, null: false, default: 0
        t.integer  :input_tokens, null: false, default: 0
        t.integer  :cached_tokens, null: false, default: 0
        t.integer  :output_tokens, null: false, default: 0
        t.decimal  :cost_usd, precision: 10, scale: 6, null: false, default: 0
        t.string   :model
        t.integer  :latency_ms
        t.text     :error
        t.timestamps
      end
      add_index :whatsapp_ai_runs, %i[shop_id created_at], name: 'idx_wa_ai_runs_shop_time'
      add_index :whatsapp_ai_runs, %i[whatsapp_conversation_id created_at], name: 'idx_wa_ai_runs_conversation'
    end
  end
end
