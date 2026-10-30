class CreateWhatsappInboundMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_inbound_messages do |t|
      t.references :shop, null: false, foreign_key: { on_delete: :cascade }
      t.references :whatsapp_account, null: false, foreign_key: { on_delete: :cascade }

      # The outbound WhatsappMessageLog this reply corresponds to, joined via
      # context.id (Meta's wamid) when present. Nullable because some inbound
      # messages aren't a reply (e.g. customer messages the merchant first).
      # SET NULL so deleting an outbound log doesn't take its inbound replies
      # with it.
      t.references :whatsapp_message_log,
                   null: true,
                   foreign_key: { to_table: :whatsapp_message_logs, on_delete: :nullify }

      t.string  :meta_message_id, null: false # wamid of this inbound message
      t.string  :parent_meta_message_id        # context.id from Meta — the wamid of the outbound we're replying to
      t.string  :from_phone,      null: false  # E.164-ish, as Meta gives it
      t.string  :kind,            null: false  # 'button' | 'interactive' | 'text' | 'other'
      t.string  :payload                       # button id / interactive reply id
      t.text    :display_text                  # what the customer saw / typed (button label, message text)
      t.datetime :received_at,    null: false
      t.jsonb   :meta_payload,    default: {}, null: false # raw entry, for debugging
      t.timestamps
    end

    # Quick lookups on the Activity page and dedup by Meta wamid.
    add_index :whatsapp_inbound_messages, :meta_message_id, unique: true
    add_index :whatsapp_inbound_messages, :parent_meta_message_id
    add_index :whatsapp_inbound_messages, [:shop_id, :received_at], order: { received_at: :desc }
  end
end
