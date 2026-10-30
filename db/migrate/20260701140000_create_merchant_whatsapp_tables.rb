# frozen_string_literal: true

class CreateMerchantWhatsappTables < ActiveRecord::Migration[7.2]
  def change
    create_table :owner_whatsapp_accounts do |t|
      t.string :waba_id
      t.string :phone_number_id
      t.text :system_user_token
      t.string :display_phone_number
      t.string :verified_name
      t.string :status, null: false, default: "disabled"
      t.string :quality_rating
      t.datetime :last_synced_at
      t.timestamps
    end

    create_table :owner_whatsapp_templates do |t|
      t.string :name, null: false
      t.string :language, null: false, default: "en"
      t.string :category, null: false, default: "UTILITY"
      t.string :status, null: false, default: "approved"
      t.text :header_text
      t.text :body_text
      t.jsonb :buttons, default: []
      t.jsonb :variable_mapping, default: {}
      t.string :meta_template_id
      t.text :description
      t.timestamps
    end
    add_index :owner_whatsapp_templates, %i[name language], unique: true

    create_table :merchant_whatsapp_rules do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :trigger_type, null: false, default: "scheduled"
      t.string :event_key
      t.string :category
      t.string :date_rule_type
      t.integer :date_rule_value
      t.string :date_rule_column
      t.jsonb :conditions, default: []
      t.string :target, null: false, default: "shops"
      t.bigint :owner_whatsapp_template_id
      t.jsonb :cta_config, default: {}
      t.integer :scheduled_hour
      t.integer :scheduled_minute
      t.boolean :active, null: false, default: false
      t.timestamps
    end
    add_index :merchant_whatsapp_rules, :slug, unique: true
    add_index :merchant_whatsapp_rules, %i[trigger_type active]
    add_index :merchant_whatsapp_rules, :event_key

    create_table :scheduled_merchant_whatsapps do |t|
      t.bigint :merchant_whatsapp_rule_id, null: false
      t.bigint :shop_id
      t.bigint :uninstalled_shop_id
      t.string :shopify_domain
      t.string :status, null: false, default: "pending"
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.bigint :merchant_whatsapp_log_id
      t.string :skip_reason
      t.timestamps
    end
    add_index :scheduled_merchant_whatsapps, %i[merchant_whatsapp_rule_id shop_id], unique: true, where: "shop_id IS NOT NULL", name: "idx_sched_mwa_rule_shop"
    add_index :scheduled_merchant_whatsapps, %i[merchant_whatsapp_rule_id uninstalled_shop_id], unique: true, where: "uninstalled_shop_id IS NOT NULL", name: "idx_sched_mwa_rule_uninstalled"
    add_index :scheduled_merchant_whatsapps, %i[status scheduled_at]

    create_table :merchant_whatsapp_opt_outs do |t|
      t.string :shopify_domain, null: false
      t.bigint :shop_id
      t.string :phone
      t.string :reason
      t.timestamps
    end
    add_index :merchant_whatsapp_opt_outs, :shopify_domain, unique: true

    create_table :merchant_whatsapp_logs do |t|
      t.bigint :merchant_whatsapp_rule_id
      t.bigint :scheduled_merchant_whatsapp_id
      t.bigint :shop_id
      t.bigint :uninstalled_shop_id
      t.string :shopify_domain
      t.string :event_key
      t.string :template_name
      t.string :recipient
      t.string :meta_message_id
      t.string :status, null: false, default: "queued"
      t.string :error_code
      t.text :error_message
      t.boolean :dry_run, null: false, default: false
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at
      t.datetime :replied_at
      t.jsonb :payload_snapshot, default: {}
      t.timestamps
    end
    add_index :merchant_whatsapp_logs, :meta_message_id
    add_index :merchant_whatsapp_logs, %i[shopify_domain created_at]
    add_index :merchant_whatsapp_logs, %i[merchant_whatsapp_rule_id status]
  end
end
