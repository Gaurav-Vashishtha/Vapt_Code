class CreateRtoIdentitiesAndStats < ActiveRecord::Migration[7.0]
  def change
    create_table :customer_identities do |t|
      t.string :phone_normalized
      t.string :email_normalized
      t.timestamps
    end

    add_index :customer_identities, :phone_normalized
    add_index :customer_identities, :email_normalized
    add_index :customer_identities, [:phone_normalized, :email_normalized], unique: true, name: "idx_customer_identities_phone_email"

    create_table :global_customer_stats do |t|
      t.references :customer_identity, null: false, foreign_key: true
      t.integer :total_orders, null: false, default: 0
      t.integer :cod_orders, null: false, default: 0
      t.integer :delivered, null: false, default: 0
      t.integer :returned, null: false, default: 0
      t.integer :rto, null: false, default: 0
      t.integer :cancelled, null: false, default: 0
      t.integer :refunded, null: false, default: 0
      t.datetime :last_order_at
      t.jsonb :extra, null: false, default: {}
      t.timestamps
    end

    add_index :global_customer_stats, :last_order_at

    create_table :global_zip_stats do |t|
      t.string :zip, null: false
      t.string :country
      t.integer :total_orders, null: false, default: 0
      t.integer :cod_orders, null: false, default: 0
      t.integer :delivered, null: false, default: 0
      t.integer :returned, null: false, default: 0
      t.integer :rto, null: false, default: 0
      t.integer :cancelled, null: false, default: 0
      t.integer :refunded, null: false, default: 0
      t.datetime :last_order_at
      t.timestamps
    end

    add_index :global_zip_stats, [:country, :zip], unique: true
  end
end

