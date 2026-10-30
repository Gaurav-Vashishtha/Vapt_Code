class CreateCustomBrandedClients < ActiveRecord::Migration[7.2]
  def change
    return if table_exists?(:custom_branded_clients)

    # The partner-facing entity behind the branded WhatsApp portal/API.
    # Deliberately NOT a shops row: these are not Shopify installs, and keeping
    # them separate means no placeholder tokens, no callback guards, and no
    # leakage into Shop.all-iterating jobs.
    create_table :custom_branded_clients do |t|
      t.string :domain, null: false
      t.string :label
      t.jsonb :metadata, default: {}, null: false
      t.datetime :last_portal_access_at
      t.timestamps
    end

    add_index :custom_branded_clients, :domain, unique: true
  end
end
