class CreateWhatsappAccounts < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_accounts do |t|
      t.references :shop, null: false, foreign_key: true, index: { unique: true }

      t.string :waba_id
      t.string :business_account_id
      t.string :phone_number_id
      t.string :display_phone_number
      t.string :verified_name
      t.string :quality_rating

      t.text :system_user_token
      t.datetime :token_expires_at

      t.integer :status, null: false, default: 0
      t.datetime :webhook_subscribed_at
      t.datetime :last_synced_at

      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :whatsapp_accounts, :waba_id
    add_index :whatsapp_accounts, :phone_number_id
    add_index :whatsapp_accounts, :status
  end
end
