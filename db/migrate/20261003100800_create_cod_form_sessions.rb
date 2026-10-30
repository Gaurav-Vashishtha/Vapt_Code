# frozen_string_literal: true

# COD Form (ARCHITECTURE.md B.8): one row per opened form (buyer session).
class CreateCodFormSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :cod_form_sessions, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.string :public_id, null: false
      t.bigint :cod_form_id
      t.integer :form_version
      t.string :status, null: false, default: "open"
      t.string :source, null: false, default: "product"
      t.boolean :is_test, null: false, default: false
      t.string :country_code
      t.string :currency
      t.string :locale
      t.string :device
      t.string :ip
      t.string :user_agent
      t.string :client_id
      t.jsonb :cart_snapshot, null: false, default: {}
      t.jsonb :quote_snapshot, null: false, default: {}
      t.jsonb :contact, null: false, default: {}
      t.string :phone_normalized
      t.string :email_normalized
      t.jsonb :address, null: false, default: {}
      t.jsonb :custom_fields, null: false, default: {}
      t.jsonb :attribution, null: false, default: {}
      t.jsonb :tracking, null: false, default: {}
      t.jsonb :ab_assignments, null: false, default: {}
      t.jsonb :otp, null: false, default: {}
      t.datetime :otp_verified_at
      t.jsonb :risk, null: false, default: {}
      t.string :idempotency_key
      t.string :order_id
      t.string :order_name
      t.bigint :order_total_cents
      t.datetime :ordered_at
      t.string :order_error
      t.bigint :partial_rule_set_id
      t.jsonb :upsell, null: false, default: {}
      t.integer :closes_count, null: false, default: 0
      t.bigint :downsell_offer_id
      t.string :recovery_token
      t.datetime :abandoned_at
      t.datetime :recovered_at
      t.bigint :abandoned_cart_id
      t.datetime :expires_at, null: false
      t.timestamps null: false
    end

    add_index :cod_form_sessions, :public_id, unique: true,
              name: "index_cod_form_sessions_on_public_id", if_not_exists: true
    add_index :cod_form_sessions, %i[shop_id created_at],
              name: "index_cod_form_sessions_on_shop_id_and_created_at", if_not_exists: true
    add_index :cod_form_sessions, %i[shop_id status updated_at],
              name: "index_cod_form_sessions_on_shop_status_updated", if_not_exists: true
    add_index :cod_form_sessions, %i[shop_id order_id],
              name: "index_cod_form_sessions_on_shop_id_and_order_id", if_not_exists: true
    add_index :cod_form_sessions, %i[shop_id idempotency_key], unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "index_cod_form_sessions_on_shop_idempotency_key", if_not_exists: true
    add_index :cod_form_sessions, %i[shop_id phone_normalized ordered_at],
              where: "order_id IS NOT NULL",
              name: "index_cod_form_sessions_on_shop_phone_ordered", if_not_exists: true
    add_index :cod_form_sessions, %i[shop_id email_normalized ordered_at],
              where: "order_id IS NOT NULL",
              name: "index_cod_form_sessions_on_shop_email_ordered", if_not_exists: true
    add_index :cod_form_sessions, %i[shop_id ip ordered_at],
              where: "order_id IS NOT NULL",
              name: "index_cod_form_sessions_on_shop_ip_ordered", if_not_exists: true
    add_index :cod_form_sessions, :recovery_token, unique: true,
              where: "recovery_token IS NOT NULL",
              name: "index_cod_form_sessions_on_recovery_token", if_not_exists: true
  end
end
