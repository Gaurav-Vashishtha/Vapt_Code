class FixCustomBrandedApiKeysOwner < ActiveRecord::Migration[7.2]
  # Repairs databases that ran the FIRST-DESIGN version of
  # 20260901090100_create_custom_branded_api_keys (keys owned by a shop)
  # before the CustomBrandedClient refactor. The table is brand new and holds
  # no real keys, so drop-and-recreate in the final shape is the simplest
  # correct fix. Databases that ran the rewritten 090100 already have the
  # client column and this is a no-op.
  def up
    return unless table_exists?(:custom_branded_api_keys)
    return if column_exists?(:custom_branded_api_keys, :custom_branded_client_id)

    drop_table :custom_branded_api_keys

    create_table :custom_branded_api_keys do |t|
      t.references :custom_branded_client, null: false, foreign_key: true,
                   index: { name: 'index_cb_api_keys_on_client_id' }
      t.string :token_digest, null: false
      t.string :label
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :custom_branded_api_keys, :token_digest, unique: true
  end

  def down; end
end
