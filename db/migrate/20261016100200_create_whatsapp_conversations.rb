# frozen_string_literal: true

class CreateWhatsappConversations < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_conversations do |t|
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.references :whatsapp_account, foreign_key: { on_delete: :nullify }, index: false
        t.string :customer_wa_id, null: false
        t.string :phone_last10, null: false
        t.string :customer_name
        t.integer :status, null: false, default: 0
        t.datetime :status_changed_at, null: false
        t.references :assignee_agent, foreign_key: { to_table: :whatsapp_inbox_agents, on_delete: :nullify }, index: false
        t.integer :unread_count, null: false, default: 0
        t.datetime :last_inbound_at, null: false
        t.string :last_inbound_meta_message_id
        t.string :read_receipt_meta_message_id
        t.datetime :last_message_at, null: false
        t.string :last_message_preview, limit: 200
        t.integer :last_message_direction, null: false, default: 0
        t.datetime :last_agent_reply_at
        t.datetime :last_auto_reply_at
        t.bigint :current_episode_id
        t.text :note
        t.datetime :unanswered_alert_sent_at
        t.datetime :window_closed_hint_at
        t.timestamps
      end
      add_index :whatsapp_conversations, %i[whatsapp_account_id customer_wa_id], unique: true,
                name: 'idx_wa_conversations_account_wa_id'
      add_index :whatsapp_conversations, %i[whatsapp_account_id phone_last10], name: 'idx_wa_conversations_account_last10'
      add_index :whatsapp_conversations, %i[shop_id phone_last10], name: 'idx_wa_conversations_shop_last10'
      add_index :whatsapp_conversations, %i[shop_id customer_wa_id], where: 'whatsapp_account_id IS NULL',
                name: 'idx_wa_conversations_orphans'
      add_index :whatsapp_conversations, %i[shop_id status last_inbound_at], order: { last_inbound_at: :desc },
                name: 'idx_wa_conversations_shop_status_inbound'
      add_index :whatsapp_conversations, %i[shop_id last_inbound_at], order: { last_inbound_at: :desc },
                name: 'idx_wa_conversations_shop_inbound'
      add_index :whatsapp_conversations, %i[shop_id assignee_agent_id status], name: 'idx_wa_conversations_assignee'
      add_index :whatsapp_conversations, :shop_id, where: 'unread_count > 0', name: 'idx_wa_conversations_unread'
      add_index :whatsapp_conversations, :status_changed_at, where: 'status = 1', name: 'idx_wa_conversations_pending_age'
    end
  end
end
