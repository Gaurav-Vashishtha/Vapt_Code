class CreateWhatsappMessageLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_message_logs do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :whatsapp_account, null: false, foreign_key: true
      t.references :whatsapp_template, null: true, foreign_key: true

      t.string :event_type_key, null: false
      t.string :template_name           # snapshot — survives template rename/delete
      t.string :recipient, null: false  # E.164-style phone, as sent
      t.string :meta_message_id         # Meta's wamid.XXX from POST /messages response

      t.integer :status, null: false, default: 0   # queued | sent | delivered | read | failed
      t.string  :error_code
      t.text    :error_message

      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at

      t.jsonb :payload_snapshot, default: {}, null: false  # debug aid

      t.timestamps
    end

    add_index :whatsapp_message_logs, :meta_message_id
    add_index :whatsapp_message_logs, [:shop_id, :status, :created_at], name: 'idx_whatsapp_logs_shop_status_time'
    add_index :whatsapp_message_logs, :event_type_key
  end
end
