# frozen_string_literal: true

# Retry state for WhatsApp messages Meta refused for a retryable reason (e.g.
# 131049 "healthy ecosystem"). One row per refused message, so the large
# message tables (twilio_logs, abandoned_carts, whatsapp_message_logs) get no
# new columns; only their existing status is updated.
class CreateWhatsappReattempts < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_reattempts do |t|
      t.string :flow, null: false                 # msg91 | bsp
      t.string :source_type, null: false          # TwilioLog | AbandonedCart | WhatsappMessageLog
      t.bigint :source_id, null: false
      t.bigint :shop_id
      t.string :status, null: false, default: 'pending' # pending | sending | sent | delivered | dropped | cancelled
      t.integer :attempts, null: false, default: 0       # resends made so far
      t.datetime :first_failed_at, null: false
      t.datetime :next_retry_at
      t.datetime :finished_at
      t.string :provider_message_id                # id of the latest attempt (MSG91 request/uuid, Meta wamid)
      t.string :error_code
      t.text :error_message
      t.string :drop_reason
      t.jsonb :request, null: false, default: {}   # MSG91: { url, body } to resend
      t.timestamps
    end

    add_index :whatsapp_reattempts, %i[source_type source_id], unique: true
    add_index :whatsapp_reattempts, %i[status next_retry_at]
    add_index :whatsapp_reattempts, :provider_message_id
    add_index :whatsapp_reattempts, %i[shop_id created_at]
  end
end
