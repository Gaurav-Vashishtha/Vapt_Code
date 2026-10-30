# frozen_string_literal: true

class AddAiFieldsToWhatsappConversations < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      change_table :whatsapp_conversations, bulk: true do |t|
        t.datetime :ai_paused_until
        t.datetime :ai_handoff_at
        t.text     :ai_draft
        t.datetime :ai_draft_at
        t.bigint   :ai_last_message_id
        t.jsonb    :ai_discount
      end
    end
  end
end
