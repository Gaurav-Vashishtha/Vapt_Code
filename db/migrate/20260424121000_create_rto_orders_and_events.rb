class CreateRtoOrdersAndEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :rto_orders do |t|
      t.references :shop_domain, null: false, foreign_key: true
      t.string :order_id, null: false
      t.string :order_number

      t.datetime :shopify_created_at
      t.datetime :shopify_updated_at
      t.datetime :processed_at
      t.datetime :cancelled_at
      t.datetime :closed_at

      t.string :financial_status
      t.string :fulfillment_status
      t.boolean :is_cod, default: false, null: false

      t.decimal :total_price, precision: 12, scale: 2
      t.string :currency
      t.string :gateway

      t.string :zip
      t.string :city
      t.string :province
      t.string :country

      # Raw PII (per your choice). Consider enabling DB encryption for these columns.
      t.string :phone
      t.string :phone_normalized
      t.string :email
      t.string :email_normalized

      # Derived outcomes
      t.datetime :delivered_at
      t.datetime :returned_at
      t.datetime :rto_at
      t.boolean :is_rto, default: false, null: false
      t.boolean :is_returned, default: false, null: false
      t.boolean :is_refunded, default: false, null: false
      t.decimal :refund_amount, precision: 12, scale: 2
      t.string :outcome_status

      t.jsonb :tags, null: false, default: []
      t.jsonb :raw_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :rto_orders, [:shop_domain_id, :order_id], unique: true
    add_index :rto_orders, :phone_normalized
    add_index :rto_orders, :email_normalized
    add_index :rto_orders, :zip
    add_index :rto_orders, :shopify_created_at
    add_index :rto_orders, :shopify_updated_at

    create_table :rto_order_events do |t|
      t.references :shop_domain, null: false, foreign_key: true
      t.string :order_id, null: false
      t.string :event_type, null: false
      t.datetime :occurred_at
      t.string :source, null: false, default: "webhook" # webhook/poll/backfill
      t.string :webhook_id
      t.jsonb :payload_json, null: false, default: {}
      t.timestamps
    end

    add_index :rto_order_events, [:shop_domain_id, :order_id]
    add_index :rto_order_events, :event_type
    add_index :rto_order_events, :occurred_at
    add_index :rto_order_events, :webhook_id
  end
end

