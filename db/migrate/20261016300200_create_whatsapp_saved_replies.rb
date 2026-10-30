# frozen_string_literal: true

class CreateWhatsappSavedReplies < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_saved_replies do |t|
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.string   :title, null: false, limit: 60
        t.string   :shortcut, null: false, limit: 30
        t.text     :body, null: false
        t.integer  :usage_count, null: false, default: 0
        t.datetime :last_used_at
        t.timestamps
      end
      add_index :whatsapp_saved_replies, 'shop_id, lower(shortcut)', unique: true, name: 'idx_wa_saved_replies_shortcut'
    end
  end
end
