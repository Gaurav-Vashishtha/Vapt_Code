# frozen_string_literal: true

class CreateWhatsappInboxLabels < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_inbox_labels do |t|
        t.references :shop, null: false, foreign_key: { on_delete: :cascade }, index: false
        t.string  :name, null: false, limit: 40
        t.string  :color, null: false, default: 'info'
        t.string  :system_key
        t.integer :position, null: false, default: 0
        t.timestamps
      end
      add_index :whatsapp_inbox_labels, 'shop_id, lower(name)', unique: true, name: 'idx_wa_inbox_labels_name'
      add_index :whatsapp_inbox_labels, %i[shop_id system_key], unique: true, where: 'system_key IS NOT NULL'
    end
  end
end
