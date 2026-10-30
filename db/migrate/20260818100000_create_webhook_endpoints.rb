# frozen_string_literal: true

class CreateWebhookEndpoints < ActiveRecord::Migration[7.2]
  def change
    create_table :webhook_endpoints do |t|
      t.bigint   :shop_id,          null: false
      t.string   :provider,         null: false
      # Shopflo's checkout_abandoned payload carries no merchant identifier at
      # all, so the shop is resolved from which URL the provider posts to.
      t.string   :endpoint_token,   null: false
      t.text     :secret
      t.string   :signature_scheme, null: false, default: 'shared_secret'
      t.string   :signature_header, null: false, default: 'X-Webhook-Signature'
      t.boolean  :enabled,          null: false, default: true
      t.jsonb    :event_config,     null: false, default: {}
      t.jsonb    :stats,            null: false, default: {}
      t.boolean  :mirror_to_slack,  null: false, default: false
      t.datetime :last_received_at
      t.timestamps
    end

    add_index :webhook_endpoints, :shop_id
    add_index :webhook_endpoints, :endpoint_token, unique: true
    add_index :webhook_endpoints, %i[shop_id provider], unique: true,
              name: 'idx_webhook_endpoints_unique_per_shop_provider'

    add_foreign_key :webhook_endpoints, :shops, on_delete: :cascade
  end
end
