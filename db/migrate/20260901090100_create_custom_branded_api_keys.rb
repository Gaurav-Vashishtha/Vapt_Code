class CreateCustomBrandedApiKeys < ActiveRecord::Migration[7.2]
  def change
    return if table_exists?(:custom_branded_api_keys)

    create_table :custom_branded_api_keys do |t|
      t.references :custom_branded_client, null: false, foreign_key: true,
                   index: { name: 'index_cb_api_keys_on_client_id' }
      # SHA256 hex digest of the bearer token. The raw token is shown exactly
      # once at mint time and never stored.
      t.string :token_digest, null: false
      t.string :label
      t.datetime :revoked_at
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :custom_branded_api_keys, :token_digest, unique: true
  end
end
