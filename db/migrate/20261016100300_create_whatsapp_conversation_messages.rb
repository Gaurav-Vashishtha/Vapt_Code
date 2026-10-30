# frozen_string_literal: true

class CreateWhatsappConversationMessages < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_conversation_messages do |t|
        t.references :whatsapp_conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.integer :direction, null: false
        t.string :source, null: false
        t.string :kind, null: false
        t.text :body
        t.jsonb :content, null: false, default: {}
        t.string :meta_message_id
        t.string :reply_to_meta_message_id
        t.references :whatsapp_inbound_message, foreign_key: { on_delete: :nullify }, index: false
        t.references :whatsapp_message_log, foreign_key: { on_delete: :nullify }, index: false
        t.references :agent, foreign_key: { to_table: :whatsapp_inbox_agents, on_delete: :nullify }, index: false
        t.integer :status
        t.string :error_code
        t.text :error_message
        t.datetime :sent_at
        t.datetime :delivered_at
        t.datetime :read_at
        t.datetime :failed_at
        t.string :media_id
        t.string :media_mime_type
        t.string :media_file_name
        t.bigint :media_size
        t.string :media_sha256
        t.integer :media_state, null: false, default: 0
        t.datetime :occurred_at, null: false
        t.timestamps
      end
      add_index :whatsapp_conversation_messages, %i[whatsapp_conversation_id occurred_at id], name: 'idx_wa_conv_msgs_thread'
      add_index :whatsapp_conversation_messages, %i[whatsapp_conversation_id updated_at], name: 'idx_wa_conv_msgs_poll'
      add_index :whatsapp_conversation_messages, :meta_message_id, unique: true, where: 'meta_message_id IS NOT NULL',
                name: 'idx_wa_conv_msgs_meta_id'
      add_index :whatsapp_conversation_messages, :whatsapp_inbound_message_id, unique: true,
                where: 'whatsapp_inbound_message_id IS NOT NULL', name: 'idx_wa_conv_msgs_inbound'
      add_index :whatsapp_conversation_messages, :whatsapp_message_log_id, unique: true,
                where: 'whatsapp_message_log_id IS NOT NULL', name: 'idx_wa_conv_msgs_log'
      add_index :whatsapp_conversation_messages, %i[shop_id agent_id created_at], where: 'agent_id IS NOT NULL',
                name: 'idx_wa_conv_msgs_agent_replies'
      add_index :whatsapp_conversation_messages, :occurred_at, where: 'media_state = 2', name: 'idx_wa_conv_msgs_media_retention'
    end
  end
end
