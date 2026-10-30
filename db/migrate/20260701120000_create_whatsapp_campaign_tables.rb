class CreateWhatsappCampaignTables < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_campaigns do |t|
      t.bigint   :shop_id, null: false
      t.bigint   :whatsapp_account_id
      t.bigint   :whatsapp_template_id
      t.bigint   :whatsapp_audience_import_id
      t.string   :name, null: false
      t.text     :description
      t.string   :status, default: 'draft', null: false
      t.string   :audience_source
      t.jsonb    :audience_filter, default: {}
      t.jsonb    :variable_mapping, default: {}
      t.string   :button_field
      t.string   :header_field
      t.jsonb    :discount_config
      t.integer  :rate_per_minute, default: 600
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :completed_at
      t.integer  :audience_count, default: 0
      t.integer  :suppressed_count, default: 0
      t.integer  :queued_count, default: 0
      t.integer  :sent_count, default: 0
      t.integer  :delivered_count, default: 0
      t.integer  :read_count, default: 0
      t.integer  :failed_count, default: 0
      t.integer  :replied_count, default: 0
      t.decimal  :estimated_cost, precision: 12, scale: 2, default: 0
      t.string   :currency
      t.timestamps
    end
    add_index :whatsapp_campaigns, %i[shop_id status]
    add_index :whatsapp_campaigns, :scheduled_at

    create_table :whatsapp_campaign_recipients do |t|
      t.bigint   :whatsapp_campaign_id, null: false
      t.bigint   :shop_id, null: false
      t.string   :phone, null: false
      t.string   :name
      t.string   :email
      t.string   :source_ref
      t.jsonb    :fields, default: {}
      t.string   :status, default: 'pending', null: false
      t.string   :suppression_reason
      t.string   :meta_message_id
      t.string   :error_code
      t.text     :error_message
      t.bigint   :whatsapp_message_log_id
      t.datetime :queued_at
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at
      t.timestamps
    end
    add_index :whatsapp_campaign_recipients, %i[whatsapp_campaign_id phone], unique: true
    add_index :whatsapp_campaign_recipients, %i[whatsapp_campaign_id status]
    add_index :whatsapp_campaign_recipients, :meta_message_id

    create_table :whatsapp_opt_outs do |t|
      t.bigint   :shop_id, null: false
      t.string   :phone_normalized, null: false
      t.string   :reason
      t.string   :source
      t.datetime :opted_out_at, null: false
      t.timestamps
    end
    add_index :whatsapp_opt_outs, %i[shop_id phone_normalized], unique: true

    create_table :whatsapp_audience_imports do |t|
      t.bigint   :shop_id, null: false
      t.string   :status, default: 'uploaded', null: false
      t.jsonb    :columns, default: []
      t.integer  :row_count, default: 0
      t.integer  :valid_count, default: 0
      t.string   :phone_column
      t.string   :name_column
      t.string   :email_column
      t.text     :error
      t.timestamps
    end
    add_index :whatsapp_audience_imports, :shop_id

    change_table :whatsapp_message_logs, bulk: true do |t|
      t.bigint :whatsapp_campaign_id
      t.bigint :whatsapp_campaign_recipient_id
    end
    add_index :whatsapp_message_logs, :whatsapp_campaign_id
  end
end
