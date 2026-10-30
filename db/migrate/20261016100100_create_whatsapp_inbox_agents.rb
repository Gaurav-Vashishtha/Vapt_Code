# frozen_string_literal: true

class CreateWhatsappInboxAgents < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_inbox_agents do |t|
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.bigint :shopify_user_id, null: false, default: 0
        t.string :name
        t.string :email
        t.boolean :account_owner, null: false, default: false
        t.datetime :last_seen_at
        t.datetime :profile_synced_at
        t.timestamps
      end
      add_index :whatsapp_inbox_agents, %i[shop_id shopify_user_id], unique: true
    end
  end
end
