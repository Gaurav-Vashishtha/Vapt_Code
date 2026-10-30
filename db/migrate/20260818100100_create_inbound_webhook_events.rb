# frozen_string_literal: true

class CreateInboundWebhookEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :inbound_webhook_events do |t|
      t.bigint   :shop_id,             null: false
      t.bigint   :webhook_endpoint_id
      t.string   :provider,            null: false
      t.string   :event_name
      t.string   :dedup_key
      t.jsonb    :payload,             null: false, default: {}
      t.integer  :status,              null: false, default: 0
      t.string   :internal_event_type_key
      t.string   :skip_reason
      t.text     :error
      t.datetime :received_at,         null: false
      t.datetime :processed_at
      t.timestamps
    end

    add_index :inbound_webhook_events, %i[shop_id received_at]
    add_index :inbound_webhook_events, %i[webhook_endpoint_id received_at],
              name: 'idx_inbound_webhook_events_endpoint'
    add_index :inbound_webhook_events, :received_at
    add_index :inbound_webhook_events, %i[shop_id status]

    # status 3 (failed) is excluded so a delivery that blew up can be re-sent
    # and reprocessed instead of being permanently deduped away.
    add_index :inbound_webhook_events, %i[shop_id dedup_key],
              unique: true,
              where: 'dedup_key IS NOT NULL AND status <> 3',
              name: 'idx_inbound_webhook_events_dedup'

    add_foreign_key :inbound_webhook_events, :shops, on_delete: :cascade
    add_foreign_key :inbound_webhook_events, :webhook_endpoints, on_delete: :nullify
  end
end
