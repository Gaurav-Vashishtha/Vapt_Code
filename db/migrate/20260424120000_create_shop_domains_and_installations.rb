class CreateShopDomainsAndInstallations < ActiveRecord::Migration[7.0]
  def change
    create_table :shop_domains do |t|
      t.string :shopify_domain, null: false
      t.datetime :last_seen_at
      t.jsonb :backfill_state, null: false, default: {}
      t.datetime :backfill_started_at
      t.datetime :backfill_completed_at
      t.datetime :last_reconciled_at
      t.datetime :last_webhook_received_at
      t.timestamps
    end

    add_index :shop_domains, :shopify_domain, unique: true

    create_table :shop_installations do |t|
      t.references :shop_domain, null: false, foreign_key: true
      t.bigint :shop_id # optional link to existing Shop record (current installation)
      t.string :status, null: false, default: "installed" # installed/uninstalled/invalid
      t.string :scopes, default: ""
      t.string :access_token
      t.datetime :installed_at
      t.datetime :uninstalled_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :shop_installations, :shop_id
    add_index :shop_installations, [:shop_domain_id, :status]
  end
end

