# frozen_string_literal: true

class CreateWhatsappConversationEpisodes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_conversation_episodes do |t|
        t.references :whatsapp_conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.datetime :opened_at, null: false
        t.datetime :first_response_at
        t.references :first_response_agent, foreign_key: { to_table: :whatsapp_inbox_agents, on_delete: :nullify }, index: false
        t.datetime :resolved_at
        t.string :resolved_by
        t.timestamps
      end
      add_index :whatsapp_conversation_episodes, %i[whatsapp_conversation_id opened_at], name: 'idx_wa_conv_episodes_conversation'
      add_index :whatsapp_conversation_episodes, %i[shop_id opened_at], name: 'idx_wa_conv_episodes_opened'
      add_index :whatsapp_conversation_episodes, %i[shop_id resolved_at], where: 'resolved_at IS NOT NULL',
                name: 'idx_wa_conv_episodes_resolved'
    end
  end
end
