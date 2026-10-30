class AddWhatsappContactsSegmentsAndCampaignRetries < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  # Release-phase rule: idempotent guards + lock_timeout so a queued ACCESS
  # EXCLUSIVE lock fails fast instead of stalling every query on the table.
  def up
    execute "SET lock_timeout = '5s'"

    unless table_exists?(:whatsapp_contacts)
      create_table :whatsapp_contacts do |t|
        t.bigint :shop_id, null: false
        t.string :phone, null: false
        t.string :name
        t.string :first_name
        t.string :last_name
        t.string :email
        t.string :source, default: 'manual', null: false
        t.jsonb :tags, default: [], null: false
        t.jsonb :attrs, default: {}, null: false
        t.boolean :subscribed, default: true, null: false
        t.integer :order_count, default: 0
        t.decimal :total_spent, precision: 12, scale: 2, default: '0.0'
        t.datetime :last_order_at
        t.string :source_ref
        t.timestamps
      end
      add_index :whatsapp_contacts, %i[shop_id phone], unique: true
      add_index :whatsapp_contacts, :tags, using: :gin
      add_index :whatsapp_contacts, %i[shop_id created_at]
    end

    unless table_exists?(:whatsapp_segments)
      create_table :whatsapp_segments do |t|
        t.bigint :shop_id, null: false
        t.string :name, null: false
        t.text :description
        t.jsonb :filters, default: {}, null: false
        t.integer :cached_count, default: 0
        t.datetime :counted_at
        t.timestamps
      end
      add_index :whatsapp_segments, :shop_id
    end

    add_column :whatsapp_campaigns, :retry_config, :jsonb, default: {} unless column_exists?(:whatsapp_campaigns, :retry_config)
    add_column :whatsapp_campaigns, :whatsapp_segment_id, :bigint unless column_exists?(:whatsapp_campaigns, :whatsapp_segment_id)

    add_column :whatsapp_campaign_recipients, :attempt_count, :integer, default: 0, null: false unless column_exists?(:whatsapp_campaign_recipients, :attempt_count)
    add_column :whatsapp_campaign_recipients, :next_retry_at, :datetime unless column_exists?(:whatsapp_campaign_recipients, :next_retry_at)
    add_column :whatsapp_campaign_recipients, :last_attempt_at, :datetime unless column_exists?(:whatsapp_campaign_recipients, :last_attempt_at)

    unless index_exists?(:whatsapp_campaign_recipients, %i[status next_retry_at], name: 'idx_wa_campaign_recipients_retry')
      add_index :whatsapp_campaign_recipients, %i[status next_retry_at],
                name: 'idx_wa_campaign_recipients_retry',
                where: "status = 'retry_pending'"
    end
  ensure
    execute "SET lock_timeout = DEFAULT"
  end

  def down
    execute "SET lock_timeout = '5s'"
    remove_index :whatsapp_campaign_recipients, name: 'idx_wa_campaign_recipients_retry' if index_exists?(:whatsapp_campaign_recipients, %i[status next_retry_at], name: 'idx_wa_campaign_recipients_retry')
    remove_column :whatsapp_campaign_recipients, :last_attempt_at if column_exists?(:whatsapp_campaign_recipients, :last_attempt_at)
    remove_column :whatsapp_campaign_recipients, :next_retry_at if column_exists?(:whatsapp_campaign_recipients, :next_retry_at)
    remove_column :whatsapp_campaign_recipients, :attempt_count if column_exists?(:whatsapp_campaign_recipients, :attempt_count)
    remove_column :whatsapp_campaigns, :whatsapp_segment_id if column_exists?(:whatsapp_campaigns, :whatsapp_segment_id)
    remove_column :whatsapp_campaigns, :retry_config if column_exists?(:whatsapp_campaigns, :retry_config)
    drop_table :whatsapp_segments if table_exists?(:whatsapp_segments)
    drop_table :whatsapp_contacts if table_exists?(:whatsapp_contacts)
  ensure
    execute "SET lock_timeout = DEFAULT"
  end
end
