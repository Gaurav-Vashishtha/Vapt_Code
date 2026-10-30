# frozen_string_literal: true

class CreateWhatsappConversationLabels < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_conversation_labels do |t|
        t.references :whatsapp_conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.references :whatsapp_inbox_label, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.string   :source, null: false, default: 'agent'
        t.datetime :created_at, null: false
      end
      add_index :whatsapp_conversation_labels, %i[whatsapp_conversation_id whatsapp_inbox_label_id], unique: true,
                name: 'idx_wa_conv_labels_unique'
      add_index :whatsapp_conversation_labels, %i[shop_id whatsapp_inbox_label_id], name: 'idx_wa_conv_labels_filter'
    end
  end
end
