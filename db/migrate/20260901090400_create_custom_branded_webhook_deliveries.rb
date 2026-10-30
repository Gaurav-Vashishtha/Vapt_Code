class CreateCustomBrandedWebhookDeliveries < ActiveRecord::Migration[7.2]
  def change
    return if table_exists?(:custom_branded_webhook_deliveries)

    # One row per relay POST to the partner webhook URL — what the portal's
    # Webhooks section renders. Pruned by the relay job (keeps the newest
    # ~500 per client), so it never grows unbounded.
    create_table :custom_branded_webhook_deliveries do |t|
      t.references :custom_branded_client, null: false, foreign_key: true,
                   index: { name: 'index_cb_webhook_deliveries_on_client_id' }
      t.string :fields
      t.jsonb :payload, default: {}, null: false
      t.integer :response_code
      t.string :error
      t.datetime :delivered_at
      t.timestamps
    end

    add_index :custom_branded_webhook_deliveries,
              %i[custom_branded_client_id created_at],
              name: 'index_cb_webhook_deliveries_recency'
  end
end
