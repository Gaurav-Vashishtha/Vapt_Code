# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_10_28_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "abandon_cart_schedules", force: :cascade do |t|
    t.string "cart_id", null: false
    t.boolean "is_sheduled"
    t.integer "schedule_count"
    t.bigint "shop_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "product_info", default: ""
    t.index ["shop_id", "cart_id", "is_sheduled"], name: "idx_acs_shop_cart_scheduled"
    t.index ["shop_id", "is_sheduled"], name: "idx_acs_shop_scheduled_lookup"
    t.index ["shop_id"], name: "index_abandon_cart_schedules_on_shop_id"
  end

  create_table "abandoned_carts", force: :cascade do |t|
    t.string "checkout_id"
    t.string "url"
    t.string "status"
    t.string "notes"
    t.string "sid"
    t.string "phone"
    t.string "country_code"
    t.string "shopify_created_at"
    t.string "notif_type"
    t.boolean "is_charged"
    t.bigint "shop_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "total_price"
    t.string "name", default: ""
    t.datetime "scheduled_at", precision: nil
    t.decimal "actual_charge_applied", precision: 8, scale: 4, default: "0.0"
    t.jsonb "dynamic_config", default: []
    t.string "featured_image", default: ""
    t.string "source", default: "shopify", null: false
    t.jsonb "source_payload", default: {}, null: false
    t.boolean "is_anchor", default: false, null: false
    t.index ["checkout_id", "notif_type", "scheduled_at"], name: "idx_abandoned_carts_lookup"
    t.index ["checkout_id"], name: "index_abandoned_carts_on_checkout_id"
    t.index ["shop_id", "checkout_id", "notif_type", "scheduled_at"], name: "idx_abandoned_carts_duplicate_check"
    t.index ["shop_id", "created_at", "notes"], name: "idx_abandoned_carts_analytics"
    t.index ["shop_id", "created_at", "total_price"], name: "idx_abandoned_carts_recovered", where: "(lower((notes)::text) = 'recovered'::text)"
    t.index ["shop_id", "created_at", "total_price"], name: "idx_abandoned_carts_sales_analytics"
    t.index ["shop_id", "created_at", "total_price"], name: "idx_ac_price_recovery", where: "((total_price IS NOT NULL) AND (lower((notes)::text) = 'recovered'::text))"
    t.index ["shop_id", "created_at"], name: "idx_abandoned_carts_anchor", where: "is_anchor"
    t.index ["shop_id", "source", "created_at"], name: "idx_abandoned_carts_source_lookup"
    t.index ["shop_id"], name: "index_abandoned_carts_on_shop_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "additional_settings", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.jsonb "third_party_payment_method_rules", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "whatsapp_language_selected", default: false, null: false
    t.boolean "pre_order_otp_draft_orders", default: false, null: false
    t.jsonb "upsell_config"
    t.jsonb "free_gift_config"
    t.index ["shop_id"], name: "index_additional_settings_on_shop_id", unique: true
  end

  create_table "backfill_leases", force: :cascade do |t|
    t.bigint "shop_domain_id", null: false
    t.string "lease_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_backfill_leases_on_expires_at"
    t.index ["lease_key"], name: "index_backfill_leases_on_lease_key", unique: true
    t.index ["shop_domain_id"], name: "index_backfill_leases_on_shop_domain_id"
  end

  create_table "billing_events", force: :cascade do |t|
    t.bigint "shop_id"
    t.string "shopify_domain"
    t.string "event_type", null: false
    t.string "old_plan"
    t.string "new_plan"
    t.decimal "amount", precision: 12, scale: 2
    t.string "currency"
    t.datetime "occurred_at", null: false
    t.string "source"
    t.string "external_id"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type", "occurred_at"], name: "index_billing_events_on_event_type_and_occurred_at"
    t.index ["external_id"], name: "index_billing_events_on_external_id"
    t.index ["occurred_at"], name: "index_billing_events_on_occurred_at"
    t.index ["shop_id"], name: "index_billing_events_on_shop_id"
  end

  create_table "black_list_shops", force: :cascade do |t|
    t.string "domain"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "branded_whatsapp_templates", force: :cascade do |t|
    t.string "template_name"
    t.string "language"
    t.string "template_type"
    t.string "variables"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "shop_id"
    t.index ["shop_id"], name: "index_branded_whatsapp_templates_on_shop_id"
  end

  create_table "call_demos", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.bigint "shop_id"
    t.datetime "scheduled_at"
    t.string "owner"
    t.string "status", default: "scheduled", null: false
    t.text "notes"
    t.string "created_by"
    t.bigint "source_call_record_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_domain"], name: "index_call_demos_on_shopify_domain"
    t.index ["status", "scheduled_at"], name: "index_call_demos_on_status_and_scheduled_at"
  end

  create_table "call_events", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.bigint "shop_id"
    t.string "event_type", null: false
    t.string "agent_name"
    t.jsonb "payload", default: {}
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_domain", "occurred_at"], name: "index_call_events_on_shopify_domain_and_occurred_at"
  end

  create_table "call_records", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.bigint "shop_id"
    t.bigint "call_target_id"
    t.string "segment"
    t.string "outcome", null: false
    t.string "agent_name"
    t.text "notes"
    t.integer "cps_at_call"
    t.datetime "called_at", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["call_target_id"], name: "index_call_records_on_call_target_id"
    t.index ["called_at"], name: "index_call_records_on_called_at"
    t.index ["shopify_domain", "called_at"], name: "index_call_records_on_shopify_domain_and_called_at"
  end

  create_table "call_reminders", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.bigint "shop_id"
    t.date "due_on", null: false
    t.text "note"
    t.string "created_by"
    t.string "status", default: "open", null: false
    t.bigint "source_call_record_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "team"
    t.string "outcome"
    t.string "completed_by"
    t.datetime "completed_at"
    t.index ["shopify_domain", "status"], name: "index_call_reminders_on_shopify_domain_and_status"
    t.index ["status", "due_on"], name: "index_call_reminders_on_status_and_due_on"
    t.index ["team", "status", "due_on"], name: "index_call_reminders_on_team_status_due_on"
  end

  create_table "call_suppressions", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.string "reason", null: false
    t.date "until_on"
    t.string "created_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_domain"], name: "index_call_suppressions_on_shopify_domain", unique: true
  end

  create_table "call_targets", force: :cascade do |t|
    t.date "call_date", null: false
    t.string "shopify_domain", null: false
    t.bigint "shop_id"
    t.string "segment", null: false
    t.integer "rank"
    t.integer "cps", default: 0
    t.integer "value_score", default: 0
    t.integer "urgency_score", default: 0
    t.jsonb "reasons", default: []
    t.string "assigned_engineer"
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["call_date", "rank"], name: "index_call_targets_on_call_date_and_rank"
    t.index ["call_date", "shopify_domain"], name: "index_call_targets_on_call_date_and_shopify_domain", unique: true
    t.index ["call_date", "status"], name: "index_call_targets_on_call_date_and_status"
  end

  create_table "callback_requests", force: :cascade do |t|
    t.string "shop_domain", null: false
    t.string "name", null: false
    t.string "phone_number", null: false
    t.string "email", null: false
    t.string "preferred_time"
    t.string "timezone"
    t.text "notes"
    t.string "status", default: "pending"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_domain", "created_at"], name: "index_callback_requests_on_shop_domain_and_created_at"
    t.index ["shop_domain"], name: "index_callback_requests_on_shop_domain"
    t.index ["status"], name: "index_callback_requests_on_status"
  end

  create_table "checkout_sessions", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.jsonb "cart_snapshot", default: {}, null: false
    t.string "anonymous_id"
    t.bigint "sso_token_id"
    t.bigint "user_id"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_checkout_sessions_on_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["shop_id"], name: "index_checkout_sessions_on_shop_id"
    t.index ["sso_token_id"], name: "index_checkout_sessions_on_sso_token_id"
  end

  create_table "churn_risk_snapshots", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "shopify_domain"
    t.date "snapshot_date", null: false
    t.integer "score", default: 0
    t.string "band"
    t.string "primary_factor"
    t.string "recommended_action"
    t.jsonb "reasons", default: []
    t.decimal "mrr", precision: 12, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "snapshot_date"], name: "index_churn_risk_snapshots_on_shop_id_and_snapshot_date", unique: true
    t.index ["snapshot_date", "band"], name: "index_churn_risk_snapshots_on_snapshot_date_and_band"
  end

  create_table "churned_stores", force: :cascade do |t|
    t.string "source_key", null: false
    t.string "churn_type", null: false
    t.string "shopify_domain", null: false
    t.datetime "churned_at", null: false
    t.bigint "uninstalled_shop_id"
    t.bigint "shop_id"
    t.string "owner_name"
    t.string "email"
    t.string "phone"
    t.string "country"
    t.date "store_created_on"
    t.datetime "installed_at"
    t.integer "tenure_days"
    t.integer "orders_processed"
    t.jsonb "features", default: [], null: false
    t.string "plan_name"
    t.decimal "plan_amount", precision: 12, scale: 2
    t.string "uninstall_reason"
    t.text "uninstall_feedback"
    t.string "currency", default: "USD"
    t.decimal "ltv_net", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "subscription_net", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "usage_net", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "adjustment_net", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "last_30d_net", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "first_charge_at"
    t.datetime "last_charge_at"
    t.boolean "returned", default: false, null: false
    t.datetime "returned_at"
    t.integer "return_gap_days"
    t.boolean "still_installed", default: false, null: false
    t.string "current_plan_name"
    t.integer "orders_since_return"
    t.decimal "net_since_return", precision: 12, scale: 2, default: "0.0", null: false
    t.integer "prior_churn_count", default: 0, null: false
    t.datetime "partner_synced_at"
    t.text "sync_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["churn_type", "churned_at"], name: "index_churned_stores_on_churn_type_and_churned_at"
    t.index ["churned_at"], name: "index_churned_stores_on_churned_at"
    t.index ["ltv_net"], name: "index_churned_stores_on_ltv_net"
    t.index ["shopify_domain"], name: "index_churned_stores_on_shopify_domain"
    t.index ["source_key"], name: "index_churned_stores_on_source_key", unique: true
  end

  create_table "cod_block_entries", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "kind", null: false
    t.string "value", null: false
    t.string "value_normalized", null: false
    t.string "note"
    t.string "created_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "kind", "value_normalized"], name: "index_cod_block_entries_on_shop_kind_value", unique: true
  end

  create_table "cod_button_configs", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "preset", default: "B", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_cod_button_configs_on_shop_id", unique: true
  end

  create_table "cod_form_admin_audits", force: :cascade do |t|
    t.string "auditable_type", null: false
    t.bigint "auditable_id"
    t.string "action", null: false
    t.jsonb "changed_fields", default: {}, null: false
    t.string "actor"
    t.string "ip"
    t.datetime "created_at", null: false
    t.index ["auditable_type", "auditable_id", "created_at"], name: "index_cod_form_admin_audits_on_auditable_and_created_at"
  end

  create_table "cod_form_country_groups", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "country_codes", default: [], null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "cod_form_daily_stats", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.date "stat_date", null: false
    t.string "dimension", default: "all", null: false
    t.string "dimension_value", default: "", null: false
    t.jsonb "metrics", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "stat_date", "dimension", "dimension_value"], name: "index_cod_form_daily_stats_unique", unique: true
  end

  create_table "cod_form_global_settings", force: :cascade do |t|
    t.boolean "kill_switch", default: false, null: false
    t.boolean "module_default_on", default: false, null: false
    t.string "at_cap_behaviour", default: "fallback", null: false
    t.integer "grace_orders", default: 0, null: false
    t.boolean "async_orders", default: false, null: false
    t.jsonb "usage_notice_thresholds", default: [50, 80, 100], null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "cod_form_integrations", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "provider", null: false
    t.string "status", default: "disconnected", null: false
    t.jsonb "credentials", default: {}, null: false
    t.jsonb "config", default: {}, null: false
    t.string "last_error"
    t.datetime "last_success_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "provider"], name: "index_cod_form_integrations_on_shop_id_and_provider", unique: true
  end

  create_table "cod_form_rejections", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "session_public_id"
    t.string "reason_code", null: false
    t.string "stage", null: false
    t.string "subject_kind"
    t.string "subject_masked"
    t.jsonb "detail", default: {}, null: false
    t.string "ip"
    t.datetime "created_at", null: false
    t.index ["shop_id", "created_at"], name: "index_cod_form_rejections_on_shop_id_and_created_at"
  end

  create_table "cod_form_sessions", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "public_id", null: false
    t.bigint "cod_form_id"
    t.integer "form_version"
    t.string "status", default: "open", null: false
    t.string "source", default: "product", null: false
    t.boolean "is_test", default: false, null: false
    t.string "country_code"
    t.string "currency"
    t.string "locale"
    t.string "device"
    t.string "ip"
    t.string "user_agent"
    t.string "client_id"
    t.jsonb "cart_snapshot", default: {}, null: false
    t.jsonb "quote_snapshot", default: {}, null: false
    t.jsonb "contact", default: {}, null: false
    t.string "phone_normalized"
    t.string "email_normalized"
    t.jsonb "address", default: {}, null: false
    t.jsonb "custom_fields", default: {}, null: false
    t.jsonb "attribution", default: {}, null: false
    t.jsonb "tracking", default: {}, null: false
    t.jsonb "ab_assignments", default: {}, null: false
    t.jsonb "otp", default: {}, null: false
    t.datetime "otp_verified_at"
    t.jsonb "risk", default: {}, null: false
    t.string "idempotency_key"
    t.string "order_id"
    t.string "order_name"
    t.bigint "order_total_cents"
    t.datetime "ordered_at"
    t.string "order_error"
    t.bigint "partial_rule_set_id"
    t.jsonb "upsell", default: {}, null: false
    t.integer "closes_count", default: 0, null: false
    t.bigint "downsell_offer_id"
    t.string "recovery_token"
    t.datetime "abandoned_at"
    t.datetime "recovered_at"
    t.bigint "abandoned_cart_id"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["public_id"], name: "index_cod_form_sessions_on_public_id", unique: true
    t.index ["recovery_token"], name: "index_cod_form_sessions_on_recovery_token", unique: true, where: "(recovery_token IS NOT NULL)"
    t.index ["shop_id", "created_at"], name: "index_cod_form_sessions_on_shop_id_and_created_at"
    t.index ["shop_id", "email_normalized", "ordered_at"], name: "index_cod_form_sessions_on_shop_email_ordered", where: "(order_id IS NOT NULL)"
    t.index ["shop_id", "idempotency_key"], name: "index_cod_form_sessions_on_shop_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["shop_id", "ip", "ordered_at"], name: "index_cod_form_sessions_on_shop_ip_ordered", where: "(order_id IS NOT NULL)"
    t.index ["shop_id", "order_id"], name: "index_cod_form_sessions_on_shop_id_and_order_id"
    t.index ["shop_id", "phone_normalized", "ordered_at"], name: "index_cod_form_sessions_on_shop_phone_ordered", where: "(order_id IS NOT NULL)"
    t.index ["shop_id", "status", "updated_at"], name: "index_cod_form_sessions_on_shop_status_updated"
  end

  create_table "cod_form_shop_configs", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "storefront_mode", default: "legacy", null: false
    t.string "module_access", default: "default", null: false
    t.datetime "enabled_at"
    t.jsonb "general", default: {}, null: false
    t.jsonb "fraud", default: {}, null: false
    t.jsonb "setup_state", default: {}, null: false
    t.jsonb "feature_overrides", default: {}, null: false
    t.jsonb "allowed_origins", default: [], null: false
    t.string "preview_token"
    t.integer "config_version", default: 0, null: false
    t.integer "metafield_synced_version", default: 0, null: false
    t.datetime "metafield_synced_at"
    t.string "asset_base"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_cod_form_shop_configs_on_shop_id", unique: true
    t.index ["storefront_mode"], name: "index_cod_form_shop_configs_on_storefront_mode"
  end

  create_table "cod_forms", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "name", default: "Default form", null: false
    t.boolean "is_default", default: false, null: false
    t.string "status", default: "active", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "targeting", default: {}, null: false
    t.string "template_key"
    t.jsonb "draft_config", default: {}, null: false
    t.jsonb "published_config", default: {}, null: false
    t.integer "published_version", default: 0, null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "status", "position"], name: "index_cod_forms_on_shop_id_and_status_and_position"
    t.index ["shop_id"], name: "index_cod_forms_one_default", unique: true, where: "is_default"
  end

  create_table "cod_king_event_logs", force: :cascade do |t|
    t.string "event_type", null: false
    t.string "session_id", null: false
    t.bigint "shop_id", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_cod_king_event_logs_on_created_at"
    t.index ["event_type", "session_id", "shop_id"], name: "unique_event_session_shop", unique: true
    t.index ["event_type"], name: "index_cod_king_event_logs_on_event_type"
    t.index ["shop_id"], name: "index_cod_king_event_logs_on_shop_id"
  end

  create_table "cod_king_stats", force: :cascade do |t|
    t.string "stat_key", null: false
    t.integer "stat_value", default: 0, null: false
    t.date "stat_date", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stat_date"], name: "index_cod_king_stats_on_stat_date"
    t.index ["stat_key", "stat_date"], name: "index_cod_king_stats_on_key_and_date", unique: true
    t.index ["stat_key"], name: "index_cod_king_stats_on_stat_key"
  end

  create_table "cod_offer_ab_tests", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "name", null: false
    t.string "offer_type", null: false
    t.string "status", default: "draft", null: false
    t.jsonb "variants", default: [], null: false
    t.datetime "started_at"
    t.datetime "stopped_at"
    t.string "winner_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "status"], name: "index_cod_offer_ab_tests_on_shop_id_and_status"
  end

  create_table "cod_offers", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "offer_type", null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.integer "priority", default: 0, null: false
    t.jsonb "targeting", default: {}, null: false
    t.jsonb "config", default: {}, null: false
    t.bigint "ab_test_id"
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ab_test_id"], name: "index_cod_offers_on_ab_test_id"
    t.index ["shop_id", "offer_type", "status", "priority"], name: "index_cod_offers_on_shop_type_status_priority"
  end

  create_table "cod_shipping_rates", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "name", null: false
    t.string "description"
    t.bigint "price_cents", default: 0, null: false
    t.string "currency"
    t.jsonb "conditions", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.string "source", default: "manual", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "active", "position"], name: "index_cod_shipping_rates_on_shop_id_and_active_and_position"
  end

  create_table "country_plan_offer_redemptions", force: :cascade do |t|
    t.bigint "country_plan_offer_id", null: false
    t.bigint "shop_id", null: false
    t.string "charge_id"
    t.string "status", default: "pending", null: false
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["charge_id"], name: "index_country_plan_offer_redemptions_on_charge_id"
    t.index ["country_plan_offer_id", "shop_id"], name: "index_country_offer_redemptions_on_offer_and_shop", unique: true
    t.index ["country_plan_offer_id"], name: "index_country_plan_offer_redemptions_on_country_plan_offer_id"
  end

  create_table "country_plan_offers", force: :cascade do |t|
    t.string "name", null: false
    t.string "country_code", null: false
    t.string "plan_name", null: false
    t.decimal "price_usd", precision: 10, scale: 2
    t.integer "trial_days"
    t.integer "max_redemptions"
    t.integer "redemptions_count", default: 0, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.boolean "active", default: false, null: false
    t.string "badge"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code", "plan_name", "active"], name: "idx_on_country_code_plan_name_active_fa87b54c69"
  end

  create_table "custom_branded_api_keys", force: :cascade do |t|
    t.bigint "custom_branded_client_id", null: false
    t.string "token_digest", null: false
    t.string "label"
    t.datetime "revoked_at"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["custom_branded_client_id"], name: "index_cb_api_keys_on_client_id"
    t.index ["token_digest"], name: "index_custom_branded_api_keys_on_token_digest", unique: true
  end

  create_table "custom_branded_clients", force: :cascade do |t|
    t.string "domain", null: false
    t.string "label"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "last_portal_access_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_custom_branded_clients_on_domain", unique: true
  end

  create_table "custom_branded_template_events", force: :cascade do |t|
    t.bigint "custom_branded_client_id", null: false
    t.bigint "whatsapp_template_id", null: false
    t.string "event_id", null: false
    t.string "event_name"
    t.string "event_group"
    t.jsonb "variables", default: [], null: false
    t.jsonb "button_variables", default: {}, null: false
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["custom_branded_client_id", "event_id"], name: "index_cb_template_events_on_client_and_event"
    t.index ["custom_branded_client_id", "event_id"], name: "index_cb_template_events_one_active_per_event", unique: true, where: "active"
    t.index ["whatsapp_template_id"], name: "index_cb_template_events_on_template_id", unique: true
  end

  create_table "custom_branded_webhook_deliveries", force: :cascade do |t|
    t.bigint "custom_branded_client_id", null: false
    t.string "fields"
    t.jsonb "payload", default: {}, null: false
    t.integer "response_code"
    t.string "error"
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["custom_branded_client_id", "created_at"], name: "index_cb_webhook_deliveries_recency"
    t.index ["custom_branded_client_id"], name: "index_cb_webhook_deliveries_on_client_id"
  end

  create_table "customer_addresses", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "company"
    t.string "address1"
    t.string "address2"
    t.string "city"
    t.string "province"
    t.string "country"
    t.string "zip"
    t.string "phone"
    t.string "province_code"
    t.string "country_code"
    t.string "country_name"
    t.string "formatted"
    t.string "formatted_area"
    t.string "latitude"
    t.string "longitude"
    t.string "coordinates_validated"
    t.string "country_code_v2"
    t.string "shopify_id"
    t.boolean "default"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "customer_id"
    t.index ["customer_id"], name: "index_customer_addresses_on_customer_id"
  end

  create_table "customer_bulk_exports", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "shopify_domain", null: false
    t.string "status", default: "requested", null: false
    t.string "bulk_operation_gid"
    t.string "shopify_status"
    t.datetime "since_at"
    t.datetime "requested_at", null: false
    t.bigint "object_count"
    t.bigint "file_size"
    t.bigint "rows_loaded", default: 0, null: false
    t.bigint "rows_failed", default: 0, null: false
    t.integer "load_attempts", default: 0, null: false
    t.text "error"
    t.datetime "load_started_at"
    t.datetime "loaded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "bytes_loaded", default: 0, null: false
    t.bigint "expected_count"
    t.datetime "progress_at"
    t.index ["shop_id", "status"], name: "index_customer_bulk_exports_on_shop_id_and_status"
    t.index ["status"], name: "index_customer_bulk_exports_on_status"
  end

  create_table "customer_identities", force: :cascade do |t|
    t.string "phone_normalized"
    t.string "email_normalized"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_normalized"], name: "index_customer_identities_on_email_normalized"
    t.index ["phone_normalized"], name: "idx_customer_identities_phone_unique", unique: true, where: "(phone_normalized IS NOT NULL)"
    t.index ["phone_normalized"], name: "index_customer_identities_on_phone_normalized"
  end

  create_table "customer_logins", force: :cascade do |t|
    t.string "shopify_customer_id"
    t.string "phone"
    t.string "email"
    t.string "password"
    t.string "shopify_domain"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "customer_pull_job_queues", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "error_message"
    t.index ["shop_id"], name: "index_customer_pull_job_queues_on_shop_id"
    t.index ["status"], name: "index_customer_pull_job_queues_on_status"
  end

  create_table "customer_shop_mappings", force: :cascade do |t|
    t.string "shopify_domain"
    t.string "shopify_customer_id"
    t.float "order_value"
    t.integer "order_count"
    t.boolean "verified_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "customer_id"
    t.string "predicted_spend_tier"
    t.string "lifetime_duration"
    t.index ["customer_id"], name: "index_customer_shop_mappings_on_customer_id"
  end

  create_table "customer_sync_controls", force: :cascade do |t|
    t.string "name", default: "global", null: false
    t.string "mode", default: "running", null: false
    t.string "reason"
    t.string "changed_by"
    t.datetime "changed_at"
    t.datetime "coordinator_heartbeat_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_customer_sync_controls_on_name", unique: true
  end

  create_table "customer_sync_states", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "shopify_customer_count", default: 0, null: false
    t.bigint "baseline_count", default: 0, null: false
    t.virtual "unloaded_count", type: :bigint, as: "GREATEST((shopify_customer_count - baseline_count), (0)::bigint)", stored: true
    t.datetime "count_synced_at"
    t.string "status", default: "idle", null: false
    t.datetime "last_attempt_at"
    t.datetime "last_success_at"
    t.datetime "next_attempt_at"
    t.integer "consecutive_failures", default: 0, null: false
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_customer_sync_states_on_shop_id", unique: true
    t.index ["status", "unloaded_count"], name: "index_customer_sync_states_on_status_and_unloaded_count"
  end

  create_table "customers", force: :cascade do |t|
    t.string "phone"
    t.string "email"
    t.string "first_name"
    t.string "last_name"
    t.string "tags"
    t.string "currency"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["phone"], name: "idx_customers_phone"
  end

  create_table "discounts", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "title", null: false
    t.string "method", null: false
    t.string "code"
    t.string "discount_type", null: false
    t.decimal "value", precision: 10, scale: 2
    t.string "applies_to", default: "all", null: false
    t.jsonb "product_gids", default: [], null: false
    t.jsonb "collection_gids", default: [], null: false
    t.jsonb "bxgy_config", default: {}, null: false
    t.string "minimum_requirement_type"
    t.decimal "minimum_requirement_value", precision: 10, scale: 2
    t.integer "usage_limit"
    t.boolean "once_per_customer", default: false, null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.boolean "combines_with_order", default: true, null: false
    t.boolean "combines_with_product", default: false, null: false
    t.boolean "combines_with_shipping", default: true, null: false
    t.boolean "widget_enabled", default: true, null: false
    t.string "headline"
    t.string "unlock_text"
    t.integer "display_order", default: 0, null: false
    t.string "shopify_gid"
    t.string "sync_status", default: "pending", null: false
    t.text "sync_error"
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "excluded_product_gids", default: [], null: false
    t.index ["shop_id", "code"], name: "index_discounts_on_shop_id_and_code", unique: true, where: "(code IS NOT NULL)"
    t.index ["shop_id", "is_active"], name: "index_discounts_on_shop_id_and_is_active"
    t.index ["shop_id", "widget_enabled"], name: "index_discounts_on_shop_id_and_widget_enabled"
    t.index ["shop_id"], name: "index_discounts_on_shop_id"
    t.index ["shopify_gid"], name: "index_discounts_on_shopify_gid"
  end

  create_table "email_click_redirects", force: :cascade do |t|
    t.string "token", null: false
    t.bigint "scheduled_email_id", null: false
    t.text "destination_url", null: false
    t.datetime "clicked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scheduled_email_id"], name: "index_email_click_redirects_on_scheduled_email_id"
    t.index ["token"], name: "index_email_click_redirects_on_token", unique: true
  end

  create_table "email_rules", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.bigint "email_template_id", null: false
    t.string "date_rule_type", null: false
    t.integer "date_rule_value", null: false
    t.json "conditions", default: []
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "date_rule_column"
    t.string "target", default: "shops", null: false
    t.integer "scheduled_hour"
    t.integer "scheduled_minute"
    t.index ["active"], name: "index_email_rules_on_active"
    t.index ["email_template_id"], name: "index_email_rules_on_email_template_id"
    t.index ["slug"], name: "index_email_rules_on_slug", unique: true
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "subject", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "exit_survey_responses", force: :cascade do |t|
    t.bigint "uninstalled_shop_id"
    t.string "shop_domain", null: false
    t.string "reason"
    t.text "feedback"
    t.string "switched_to"
    t.string "missing_feature"
    t.string "win_back"
    t.string "return_likelihood"
    t.boolean "wants_callback", default: false, null: false
    t.string "callback_phone"
    t.datetime "submitted_at", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reason", "submitted_at"], name: "index_exit_survey_responses_on_reason_and_submitted_at"
    t.index ["shop_domain"], name: "index_exit_survey_responses_on_shop_domain"
    t.index ["submitted_at"], name: "index_exit_survey_responses_on_submitted_at"
    t.index ["uninstalled_shop_id"], name: "index_exit_survey_responses_on_uninstalled_shop_id"
  end

  create_table "feature_adoption_events", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "feature_key", null: false
    t.datetime "first_enabled_at"
    t.datetime "first_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "feature_key"], name: "index_feature_adoption_events_on_shop_id_and_feature_key", unique: true
  end

  create_table "feature_gates", force: :cascade do |t|
    t.string "feature_key", null: false
    t.string "min_tier", default: "free", null: false
    t.boolean "enabled", default: true, null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_key"], name: "index_feature_gates_on_feature_key", unique: true
  end

  create_table "follow_up_comments", force: :cascade do |t|
    t.bigint "follow_up_id", null: false
    t.text "comment", null: false
    t.string "commented_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["follow_up_id"], name: "index_follow_up_comments_on_follow_up_id"
  end

  create_table "follow_ups", force: :cascade do |t|
    t.bigint "shop_id"
    t.string "source_tab", null: false
    t.text "notes", null: false
    t.string "status", default: "pending", null: false
    t.text "resolved_notes"
    t.datetime "resolved_at"
    t.string "resolved_by"
    t.string "resolved_source_tab"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "uninstalled_shop_id"
    t.index ["shop_id"], name: "index_follow_ups_on_shop_id"
    t.index ["status"], name: "index_follow_ups_on_status"
    t.index ["uninstalled_shop_id"], name: "index_follow_ups_on_uninstalled_shop_id"
  end

  create_table "form_funnel_events", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "session_token"
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_token"], name: "index_form_funnel_events_on_session_token"
    t.index ["shop_id", "event_type", "occurred_at"], name: "idx_on_shop_id_event_type_occurred_at_57f4454db4"
    t.index ["shop_id", "session_token"], name: "index_form_funnel_events_on_shop_id_and_session_token"
    t.index ["shop_id"], name: "index_form_funnel_events_on_shop_id"
  end

  create_table "form_order_usages", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "period", null: false
    t.integer "orders_count", default: 0, null: false
    t.integer "partial_orders_count", default: 0, null: false
    t.integer "test_orders_count", default: 0, null: false
    t.integer "over_cap_count", default: 0, null: false
    t.integer "overage_billed_count", default: 0, null: false
    t.integer "cap_snapshot"
    t.datetime "notified_80_at"
    t.datetime "notified_100_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "notified_50_at"
    t.index ["shop_id", "period"], name: "index_form_order_usages_on_shop_id_and_period", unique: true
  end

  create_table "global_customer_stats", force: :cascade do |t|
    t.bigint "customer_identity_id", null: false
    t.integer "total_orders", default: 0, null: false
    t.integer "cod_orders", default: 0, null: false
    t.integer "delivered", default: 0, null: false
    t.integer "returned", default: 0, null: false
    t.integer "rto", default: 0, null: false
    t.integer "cancelled", default: 0, null: false
    t.integer "refunded", default: 0, null: false
    t.datetime "last_order_at"
    t.jsonb "extra", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "smoothed_rto_rate"
    t.float "rto_logit_contribution", default: 0.0, null: false
    t.datetime "score_computed_at"
    t.index ["customer_identity_id"], name: "index_global_customer_stats_on_customer_identity_id"
    t.index ["last_order_at"], name: "index_global_customer_stats_on_last_order_at"
    t.index ["rto_logit_contribution"], name: "index_global_customer_stats_on_rto_logit_contribution"
  end

  create_table "global_settings", force: :cascade do |t|
    t.text "cod_include_tags"
    t.text "cod_exclude_tags"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "send_fulfilment_on_update_shops"
  end

  create_table "global_zip_stats", force: :cascade do |t|
    t.string "zip", null: false
    t.string "country"
    t.integer "total_orders", default: 0, null: false
    t.integer "cod_orders", default: 0, null: false
    t.integer "delivered", default: 0, null: false
    t.integer "returned", default: 0, null: false
    t.integer "rto", default: 0, null: false
    t.integer "cancelled", default: 0, null: false
    t.integer "refunded", default: 0, null: false
    t.datetime "last_order_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "smoothed_rto_rate"
    t.float "rto_logit_contribution", default: 0.0, null: false
    t.datetime "score_computed_at"
    t.index ["country", "zip"], name: "index_global_zip_stats_on_country_and_zip", unique: true
    t.index ["rto_logit_contribution"], name: "index_global_zip_stats_on_rto_logit_contribution"
  end

  create_table "headers", force: :cascade do |t|
    t.string "header_id", default: ""
    t.string "country_codes", default: ""
    t.string "dlt_principal_entity_id", default: ""
    t.string "status", default: "requested", null: false
    t.bigint "shop_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_headers_on_shop_id"
  end

  create_table "inbound_webhook_events", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "webhook_endpoint_id"
    t.string "provider", null: false
    t.string "event_name"
    t.string "dedup_key"
    t.jsonb "payload", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.string "internal_event_type_key"
    t.string "skip_reason"
    t.text "error"
    t.datetime "received_at", null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["received_at"], name: "index_inbound_webhook_events_on_received_at"
    t.index ["shop_id", "dedup_key"], name: "idx_inbound_webhook_events_dedup", unique: true, where: "((dedup_key IS NOT NULL) AND (status <> 3))"
    t.index ["shop_id", "received_at"], name: "index_inbound_webhook_events_on_shop_id_and_received_at"
    t.index ["shop_id", "status"], name: "index_inbound_webhook_events_on_shop_id_and_status"
    t.index ["webhook_endpoint_id", "received_at"], name: "idx_inbound_webhook_events_endpoint"
  end

  create_table "integrations", force: :cascade do |t|
    t.boolean "active"
    t.string "provider"
    t.text "provider_api_key"
    t.string "provider_sender_id"
    t.bigint "shop_id", null: false
    t.index ["shop_id"], name: "index_integrations_on_shop_id"
  end

  create_table "job_locks", force: :cascade do |t|
    t.string "job_name", null: false
    t.datetime "locked_at", precision: nil, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_name"], name: "index_job_locks_on_job_name", unique: true
  end

  create_table "lead_collections", force: :cascade do |t|
    t.string "email", null: false
    t.string "phone_number", null: false
    t.string "preferred_time_to_connect", null: false
    t.string "website"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "purpose", default: "product_demo", null: false
    t.text "notes"
    t.index ["created_at"], name: "index_lead_collections_on_created_at"
    t.index ["email"], name: "index_lead_collections_on_email"
    t.index ["purpose"], name: "index_lead_collections_on_purpose"
  end

  create_table "locations", force: :cascade do |t|
    t.string "country"
    t.string "zipcode"
    t.string "province"
    t.string "city"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["zipcode", "country"], name: "index_locations_on_zipcode_and_country"
  end

  create_table "locks", force: :cascade do |t|
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["value"], name: "index_locks_on_value", unique: true
  end

  create_table "merchant_whatsapp_logs", force: :cascade do |t|
    t.bigint "merchant_whatsapp_rule_id"
    t.bigint "scheduled_merchant_whatsapp_id"
    t.bigint "shop_id"
    t.bigint "uninstalled_shop_id"
    t.string "shopify_domain"
    t.string "event_key"
    t.string "template_name"
    t.string "recipient"
    t.string "meta_message_id"
    t.string "status", default: "queued", null: false
    t.string "error_code"
    t.text "error_message"
    t.boolean "dry_run", default: false, null: false
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "read_at"
    t.datetime "failed_at"
    t.datetime "replied_at"
    t.jsonb "payload_snapshot", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_whatsapp_rule_id", "status"], name: "idx_on_merchant_whatsapp_rule_id_status_a1b8191bab"
    t.index ["meta_message_id"], name: "index_merchant_whatsapp_logs_on_meta_message_id"
    t.index ["shopify_domain", "created_at"], name: "index_merchant_whatsapp_logs_on_shopify_domain_and_created_at"
  end

  create_table "merchant_whatsapp_opt_outs", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.bigint "shop_id"
    t.string "phone"
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_domain"], name: "index_merchant_whatsapp_opt_outs_on_shopify_domain", unique: true
  end

  create_table "merchant_whatsapp_rules", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "trigger_type", default: "scheduled", null: false
    t.string "event_key"
    t.string "category"
    t.string "date_rule_type"
    t.integer "date_rule_value"
    t.string "date_rule_column"
    t.jsonb "conditions", default: []
    t.string "target", default: "shops", null: false
    t.bigint "owner_whatsapp_template_id"
    t.jsonb "cta_config", default: {}
    t.integer "scheduled_hour"
    t.integer "scheduled_minute"
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variable_mapping", default: {}
    t.index ["event_key"], name: "index_merchant_whatsapp_rules_on_event_key"
    t.index ["slug"], name: "index_merchant_whatsapp_rules_on_slug", unique: true
    t.index ["trigger_type", "active"], name: "index_merchant_whatsapp_rules_on_trigger_type_and_active"
  end

  create_table "mrr_snapshots", force: :cascade do |t|
    t.bigint "shop_id"
    t.string "shopify_domain"
    t.date "snapshot_date", null: false
    t.string "plan_name"
    t.decimal "plan_price", precision: 10, scale: 2, default: "0.0"
    t.decimal "usage_trailing_30d", precision: 12, scale: 2, default: "0.0"
    t.decimal "mrr", precision: 12, scale: 2, default: "0.0"
    t.string "currency"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["snapshot_date", "shop_id"], name: "index_mrr_snapshots_on_snapshot_date_and_shop_id", unique: true
    t.index ["snapshot_date"], name: "index_mrr_snapshots_on_snapshot_date"
  end

  create_table "notification_logs", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "template_name", null: false
    t.datetime "scheduled_at", precision: nil, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "clicked_at"
    t.index ["shop_id", "template_name", "scheduled_at"], name: "index_logs_on_shop_template_time", unique: true
    t.index ["shop_id"], name: "index_notification_logs_on_shop_id"
  end

  create_table "notification_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "subject", null: false
    t.string "view_file", null: false
    t.string "trigger_type", null: false
    t.jsonb "trigger_params", default: {}
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_notification_templates_on_name", unique: true
  end

  create_table "onboarding_events", force: :cascade do |t|
    t.bigint "shop_id"
    t.string "event", null: false
    t.integer "step"
    t.string "feature", default: "quick-onboarding-v2", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "shopify_domain"
    t.string "country_code"
    t.string "shop_created_date"
    t.index ["country_code"], name: "index_onboarding_events_on_country_code"
    t.index ["event", "occurred_at"], name: "index_onboarding_events_on_event_and_occurred_at"
    t.index ["event", "shopify_domain"], name: "index_onboarding_events_on_event_and_shopify_domain"
    t.index ["shop_id", "occurred_at"], name: "index_onboarding_events_on_shop_id_and_occurred_at"
    t.index ["shop_id"], name: "index_onboarding_events_on_shop_id"
  end

  create_table "ops_daily_snapshots", force: :cascade do |t|
    t.date "stat_date", null: false
    t.integer "active_subscriptions", default: 0, null: false
    t.decimal "mrr_usd", precision: 14, scale: 2, default: "0.0", null: false
    t.integer "shops_scanned", default: 0, null: false
    t.jsonb "plan_breakdown", default: {}, null: false
    t.boolean "complete", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stat_date"], name: "index_ops_daily_snapshots_on_stat_date", unique: true
  end

  create_table "ops_dynamic_charge_dailies", force: :cascade do |t|
    t.date "stat_date", null: false
    t.integer "runs", default: 0, null: false
    t.integer "charges", default: 0, null: false
    t.integer "failed_charges", default: 0, null: false
    t.integer "capped_shops", default: 0, null: false
    t.integer "below_threshold", default: 0, null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "sms", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "whatsapp", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "whatsapp_bsp", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "preorder", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "abandoned_sms", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "abandoned_whatsapp", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "ivr", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "prepaid", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "partial_payment", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stat_date"], name: "idx_ops_dynamic_charge_dailies_date", unique: true
  end

  create_table "ops_gmv_dailies", force: :cascade do |t|
    t.date "stat_date", null: false
    t.string "currency", default: "INR", null: false
    t.boolean "is_cod", default: false, null: false
    t.integer "orders", default: 0, null: false
    t.decimal "gmv", precision: 16, scale: 2, default: "0.0", null: false
    t.integer "unparsed_orders", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stat_date", "currency", "is_cod"], name: "idx_ops_gmv_dailies_key", unique: true
  end

  create_table "order_confirmations", force: :cascade do |t|
    t.string "order_id"
    t.string "order_amount"
    t.string "customer_name"
    t.string "customer_number"
    t.string "status"
    t.datetime "confirmed_at", precision: nil
    t.bigint "shop_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "otp_secret_key"
    t.string "ivr_sid"
    t.boolean "is_charged", default: false
    t.string "country_code"
    t.string "ver_type"
    t.integer "notif_count", default: 0
    t.string "order_status_url"
    t.string "order_number"
    t.string "customer_locale"
    t.string "customer_id"
    t.string "customer_email"
    t.string "currency"
    t.string "prepaid_link"
    t.string "draft_payment_gateway"
    t.string "draft_order_id"
    t.string "draft_order_uuid"
    t.string "shipping_address"
    t.string "persisted_otp"
    t.boolean "is_max_tried"
    t.boolean "is_retried", default: false
    t.decimal "cod_fee", default: "0.0"
    t.string "digest"
    t.boolean "is_prepaid_charged"
    t.string "source_name"
    t.string "payment_link_id"
    t.string "phonepe_transaction_ids", default: ""
    t.string "checkout_token"
    t.string "prepaid_status", default: ""
    t.boolean "is_cod_order", default: false
    t.string "partial_payment_variants", default: ""
    t.boolean "receipt_email_sent", default: false
    t.string "shipping_status"
    t.boolean "is_otp_verified", default: false, null: false
    t.jsonb "conversion_context", default: {}, null: false
    t.index "shop_id, \"right\"(regexp_replace((customer_number)::text, '\\D'::text, ''::text, 'g'::text), 10), created_at", name: "idx_oc_shop_phone_last10"
    t.index ["checkout_token"], name: "index_order_confirmations_on_checkout_token"
    t.index ["created_at"], name: "idx_oc_created_at_brin", using: :brin
    t.index ["digest"], name: "index_order_confirmations_on_digest"
    t.index ["draft_order_uuid"], name: "index_order_confirmations_on_draft_order_uuid"
    t.index ["order_id"], name: "index_order_confirmations_on_order_id"
    t.index ["order_status_url"], name: "index_order_confirmations_on_order_status_url"
    t.index ["prepaid_status", "created_at"], name: "idx_order_confirmations_prepaid_status_created_at"
    t.index ["shop_id", "created_at", "is_cod_order"], name: "idx_order_confirmations_cod_breakdown"
    t.index ["shop_id", "created_at", "is_cod_order"], name: "idx_order_type_breakdown"
    t.index ["shop_id", "created_at", "order_amount"], name: "idx_oc_amount_analytics", where: "((order_amount IS NOT NULL) AND ((order_amount)::text <> ''::text))"
    t.index ["shop_id", "created_at", "order_amount"], name: "idx_order_confirmations_analytics_core"
    t.index ["shop_id", "created_at", "order_amount"], name: "idx_order_confirmations_cod_only", where: "((is_cod_order = true) AND (order_amount IS NOT NULL) AND ((order_amount)::text <> ''::text))"
    t.index ["shop_id", "created_at", "order_amount"], name: "idx_order_confirmations_partial_payments", where: "(((status)::text = 'COD-Partial-Payment-Received'::text) AND (order_amount IS NOT NULL) AND ((order_amount)::text <> ''::text))"
    t.index ["shop_id", "created_at", "order_amount"], name: "idx_order_confirmations_prepaid_only", where: "((is_cod_order = false) AND (order_amount IS NOT NULL) AND ((order_amount)::text <> ''::text))"
    t.index ["shop_id", "created_at", "status", "order_amount"], name: "idx_order_confirmations_partial_payment"
    t.index ["shop_id", "created_at", "status"], name: "idx_oc_daily_analytics", where: "((status)::text <> 'Test-Order'::text)"
    t.index ["shop_id", "created_at"], name: "idx_aov_calculations", where: "((order_amount IS NOT NULL) AND ((order_amount)::text <> ''::text) AND ((order_amount)::double precision > (0)::double precision))"
    t.index ["shop_id", "created_at"], name: "idx_cod_prepaid_orders", where: "((status)::text = 'COD-Prepaid'::text)"
    t.index ["shop_id", "created_at"], name: "idx_oc_aov_calc", where: "(((status)::text <> 'Test-Order'::text) AND (order_amount IS NOT NULL) AND ((order_amount)::text <> ''::text))"
    t.index ["shop_id", "created_at"], name: "idx_order_confirmations_valid_amounts", where: "((order_amount IS NOT NULL) AND ((order_amount)::text <> ''::text))"
    t.index ["shop_id", "created_at"], name: "idx_verified_orders", where: "((status)::text = 'COD-Verified'::text)"
    t.index ["shop_id", "is_cod_order", "created_at", "order_amount"], name: "idx_oc_daily_sales_enhanced", where: "(((status)::text <> 'Test-Order'::text) AND (order_amount IS NOT NULL))"
    t.index ["shop_id", "is_otp_verified", "created_at"], name: "idx_oc_shop_otp_verified_created_at"
    t.index ["shop_id", "order_number"], name: "idx_oc_shop_order_number"
    t.index ["shop_id", "shipping_status", "created_at"], name: "idx_oc_shop_shipping_status_created_at"
    t.index ["shop_id", "status", "created_at"], name: "idx_oc_status_summary", where: "((status)::text = ANY ((ARRAY['COD-Verified'::character varying, 'COD-Prepaid'::character varying, 'COD-Partial-Payment-Received'::character varying])::text[]))"
    t.index ["shop_id", "status", "created_at"], name: "idx_order_confirmations_status_analytics"
    t.index ["shop_id"], name: "index_order_confirmations_on_shop_id"
  end

  create_table "order_metrics", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "order_id", null: false
    t.bigint "order_confirmation_id"
    t.string "order_name"
    t.datetime "ordered_at", null: false
    t.string "currency"
    t.boolean "is_cod", default: false, null: false
    t.decimal "total_price", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "original_total", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "discount_total", precision: 12, scale: 2, default: "0.0", null: false
    t.jsonb "discounts", default: [], null: false
    t.decimal "prepaid_discount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "cod_fee", precision: 12, scale: 2, default: "0.0", null: false
    t.string "cod_fee_source"
    t.boolean "is_partial", default: false, null: false
    t.decimal "partial_upfront", precision: 12, scale: 2, default: "0.0", null: false
    t.boolean "is_converted_prepaid", default: false, null: false
    t.string "converted_from_order_id"
    t.boolean "is_otp_verified", default: false, null: false
    t.boolean "is_cod_form", default: false, null: false
    t.boolean "is_ac_recovered", default: false, null: false
    t.string "widget_session_id"
    t.string "delivery_status", default: "unfulfilled", null: false
    t.datetime "delivered_at"
    t.datetime "rto_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "upsell_revenue", precision: 12, scale: 2
    t.integer "upsell_items"
    t.integer "free_gift_items"
    t.decimal "free_gift_value", precision: 12, scale: 2
    t.jsonb "free_gift_rule_ids"
    t.index ["shop_id", "delivery_status", "ordered_at"], name: "idx_order_metrics_delivery"
    t.index ["shop_id", "order_id"], name: "index_order_metrics_on_shop_id_and_order_id", unique: true
    t.index ["shop_id", "ordered_at"], name: "idx_order_metrics_ac_recovered", where: "is_ac_recovered"
    t.index ["shop_id", "ordered_at"], name: "idx_order_metrics_cod_fee", where: "(cod_fee > (0)::numeric)"
    t.index ["shop_id", "ordered_at"], name: "idx_order_metrics_cod_form", where: "is_cod_form"
    t.index ["shop_id", "ordered_at"], name: "idx_order_metrics_converted", where: "is_converted_prepaid"
    t.index ["shop_id", "ordered_at"], name: "idx_order_metrics_free_gift", where: "(free_gift_items > 0)"
    t.index ["shop_id", "ordered_at"], name: "idx_order_metrics_otp_verified", where: "is_otp_verified"
    t.index ["shop_id", "ordered_at"], name: "idx_order_metrics_partial", where: "is_partial"
    t.index ["shop_id", "ordered_at"], name: "idx_order_metrics_prepaid_discount", where: "(prepaid_discount > (0)::numeric)"
    t.index ["shop_id", "ordered_at"], name: "idx_order_metrics_upsell", where: "(upsell_items > 0)"
    t.index ["shop_id", "ordered_at"], name: "index_order_metrics_on_shop_id_and_ordered_at"
  end

  create_table "owner_whatsapp_accounts", force: :cascade do |t|
    t.string "waba_id"
    t.string "phone_number_id"
    t.text "system_user_token"
    t.string "display_phone_number"
    t.string "verified_name"
    t.string "status", default: "disabled", null: false
    t.string "quality_rating"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "owner_whatsapp_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "language", default: "en", null: false
    t.string "category", default: "UTILITY", null: false
    t.string "status", default: "approved", null: false
    t.text "header_text"
    t.text "body_text"
    t.jsonb "buttons", default: []
    t.jsonb "variable_mapping", default: {}
    t.string "meta_template_id"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "components", default: []
    t.text "footer_text"
    t.index ["name", "language"], name: "index_owner_whatsapp_templates_on_name_and_language", unique: true
  end

  create_table "partial_product_mappings", force: :cascade do |t|
    t.string "partial_product_id"
    t.string "partial_variant_id"
    t.string "original_variant_ids", array: true
    t.boolean "is_deleted", default: false
    t.string "shopify_domain"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "original_cost", default: "0.0"
    t.string "session_id", default: ""
    t.bigint "cart_rule_id", default: 0
    t.string "cart_hash"
    t.decimal "partial_price", default: "0.0"
    t.index ["partial_variant_id"], name: "idx_partial_mappings_variant"
    t.index ["shopify_domain", "cart_hash", "session_id"], name: "index_mappings_on_domain_hash_session"
    t.index ["shopify_domain", "cart_hash"], name: "index_partial_product_mappings_on_shopify_domain_and_cart_hash"
    t.index ["shopify_domain", "session_id", "cart_rule_id"], name: "index_mappings_on_domain_session_cart_rule"
  end

  create_table "partial_rule_sets", force: :cascade do |t|
    t.string "rule_name"
    t.decimal "amount"
    t.string "amount_type"
    t.string "product_ids", array: true
    t.boolean "is_all", default: false
    t.boolean "is_enabled", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "shop_id"
    t.boolean "is_cart_rule", default: false
    t.string "discount_code", default: ""
    t.decimal "discount_value", default: "0.0"
    t.string "discount_type", default: "fixed"
    t.string "amount_to_show", default: ""
    t.string "sub_heading", default: ""
    t.decimal "min_cart_range", default: "0.0"
    t.decimal "max_cart_range", default: "0.0"
    t.integer "position", default: 0, null: false
    t.string "product_scope", default: "all", null: false
    t.string "description_template", default: ""
    t.boolean "zipcode_blacklist_enabled", default: false, null: false
    t.text "zipcode_blacklist", default: "", null: false
    t.string "variant_scope", default: "all", null: false
    t.string "variant_ids", default: [], null: false, array: true
    t.boolean "include_cod_fee", default: false, null: false
    t.decimal "cod_fee_amount", default: "0.0"
    t.string "collection_scope", default: "all", null: false
    t.string "collection_ids", default: [], null: false, array: true
    t.boolean "match_any_product", default: false, null: false
    t.boolean "zipcode_whitelist_enabled", default: false, null: false
    t.text "zipcode_whitelist", default: "", null: false
    t.boolean "checkout_cod_only", default: false, null: false
    t.decimal "shipping_charge"
    t.string "custom_save_text"
    t.jsonb "rto_engine"
    t.jsonb "cart_items_range"
    t.jsonb "phone_blacklist"
    t.jsonb "email_blacklist"
    t.boolean "free_delivery"
    t.jsonb "repeat_customer_discount"
    t.jsonb "cod_cooling_period"
    t.string "shipping_charge_text"
    t.index ["shop_id", "position"], name: "index_partial_rule_sets_on_shop_id_and_position"
    t.index ["shop_id"], name: "index_partial_rule_sets_on_shop_id"
  end

  create_table "partner_app_events", force: :cascade do |t|
    t.string "event_type", null: false
    t.string "shopify_domain", null: false
    t.string "shop_gid"
    t.datetime "occurred_at", null: false
    t.string "charge_id"
    t.string "charge_name"
    t.decimal "charge_amount", precision: 12, scale: 2
    t.string "currency"
    t.boolean "charge_test", default: false, null: false
    t.string "reason"
    t.text "description"
    t.string "external_key", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type", "occurred_at"], name: "index_partner_app_events_on_event_type_and_occurred_at"
    t.index ["external_key"], name: "index_partner_app_events_on_external_key", unique: true
    t.index ["shopify_domain", "occurred_at"], name: "index_partner_app_events_on_shopify_domain_and_occurred_at"
  end

  create_table "partner_sales", force: :cascade do |t|
    t.string "shopify_domain"
    t.string "sale_type", null: false
    t.string "charge_id"
    t.decimal "gross_amount", precision: 12, scale: 2
    t.decimal "net_amount", precision: 12, scale: 2
    t.string "currency"
    t.datetime "occurred_at", null: false
    t.string "external_id", null: false
    t.string "app_name"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "app_id"
    t.index ["app_id", "occurred_at"], name: "index_partner_sales_on_app_id_and_occurred_at"
    t.index ["external_id"], name: "index_partner_sales_on_external_id", unique: true
    t.index ["sale_type", "occurred_at"], name: "index_partner_sales_on_sale_type_and_occurred_at"
    t.index ["shopify_domain"], name: "index_partner_sales_on_shopify_domain"
  end

  create_table "payment_reconciliations", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "provider", null: false
    t.string "provider_order_id", null: false
    t.string "provider_payment_id"
    t.string "internal_reference"
    t.string "status", default: "pending", null: false
    t.string "last_provider_status"
    t.integer "reconcile_attempts_count", default: 0, null: false
    t.datetime "last_reconciled_at"
    t.datetime "next_reconcile_at"
    t.datetime "reconcile_until_at", null: false
    t.string "last_webhook_event_id"
    t.datetime "last_webhook_event_at"
    t.text "last_error"
    t.jsonb "cart_payload", default: {}, null: false
    t.jsonb "customer_payload", default: {}, null: false
    t.jsonb "store_payload", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "shopify_order_id"
    t.integer "shopify_order_number"
    t.string "shopify_order_name"
    t.jsonb "conversion_context", default: {}, null: false
    t.index ["provider", "provider_order_id"], name: "idx_payment_recon_provider_order_unique", unique: true
    t.index ["provider_payment_id"], name: "index_payment_reconciliations_on_provider_payment_id"
    t.index ["reconcile_until_at"], name: "index_payment_reconciliations_on_reconcile_until_at"
    t.index ["shop_id"], name: "index_payment_reconciliations_on_shop_id"
    t.index ["shopify_order_id"], name: "index_payment_reconciliations_on_shopify_order_id"
    t.index ["status", "next_reconcile_at"], name: "idx_payment_recon_status_next_reconcile"
  end

  create_table "payout_earnings", force: :cascade do |t|
    t.bigint "payout_id", null: false
    t.bigint "referral_earning_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payout_id", "referral_earning_id"], name: "index_payout_earnings_unique", unique: true
    t.index ["payout_id"], name: "index_payout_earnings_on_payout_id"
    t.index ["referral_earning_id"], name: "index_payout_earnings_on_referral_earning_id"
  end

  create_table "payouts", force: :cascade do |t|
    t.bigint "referral_partner_id", null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "USD", null: false
    t.string "status", default: "pending", null: false
    t.string "payment_method", null: false
    t.text "payment_details"
    t.date "payout_date", null: false
    t.date "earnings_from_date", null: false
    t.date "earnings_to_date", null: false
    t.text "notes"
    t.string "transaction_reference"
    t.string "created_by"
    t.datetime "processed_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["earnings_from_date", "earnings_to_date"], name: "index_payouts_on_earnings_date_range"
    t.index ["payout_date"], name: "index_payouts_on_payout_date"
    t.index ["referral_partner_id"], name: "index_payouts_on_referral_partner_id"
    t.index ["status"], name: "index_payouts_on_status"
  end

  create_table "persisted_settings", force: :cascade do |t|
    t.integer "test_order_count"
    t.string "shopify_domain"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "plan_limits", force: :cascade do |t|
    t.string "scope_type", null: false
    t.string "scope_key", null: false
    t.string "plan_tier"
    t.integer "monthly_cap"
    t.string "at_cap_behaviour"
    t.integer "grace_orders"
    t.decimal "overage_rate", precision: 10, scale: 4
    t.boolean "active", default: true, null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scope_type", "scope_key", "plan_tier"], name: "index_plan_limits_on_scope_type_and_scope_key_and_plan_tier", unique: true
  end

  create_table "plans", force: :cascade do |t|
    t.string "name"
    t.string "price"
    t.string "strike_price"
    t.boolean "recommended"
    t.integer "max_sms"
    t.integer "cod_form_orders"
  end

  create_table "pre_order_otp_draft_orders", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "device_id", null: false
    t.bigint "pre_order_otp_id"
    t.string "phone_digits"
    t.string "draft_order_gid"
    t.string "draft_order_name"
    t.string "cart_fingerprint"
    t.string "status", default: "pending", null: false
    t.string "shopify_order_id"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "device_id"], name: "idx_otp_drafts_shop_device", unique: true
    t.index ["shop_id", "phone_digits", "status"], name: "idx_otp_drafts_shop_phone_status"
  end

  create_table "pre_order_otps", force: :cascade do |t|
    t.string "ip_address"
    t.string "phone"
    t.boolean "status"
    t.string "notes"
    t.string "sid"
    t.string "country_code"
    t.string "device_id"
    t.boolean "is_charged"
    t.bigint "shop_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "otp"
    t.decimal "actual_charge_applied", precision: 8, scale: 4, default: "0.0"
    t.string "shopify_order_ids"
    t.json "cart_details", default: [], array: true
    t.string "order_status", default: "IN_PROGRESS"
    t.string "verification_status", default: ""
    t.string "ver_type", default: "SMS", null: false
    t.text "internal_comment"
    t.index ["device_id", "created_at"], name: "index_pre_order_otps_on_device_id_and_created_at"
    t.index ["device_id", "shop_id"], name: "idx_pre_otps_device_shop"
    t.index ["device_id"], name: "index_pre_order_otps_on_device_id"
    t.index ["ip_address", "created_at"], name: "index_pre_order_otps_on_ip_address_and_created_at"
    t.index ["ip_address"], name: "index_pre_order_otps_on_ip_address"
    t.index ["phone", "created_at"], name: "index_pre_order_otps_on_phone_and_created_at"
    t.index ["phone"], name: "index_pre_order_otps_on_phone"
    t.index ["shop_id", "created_at", "status"], name: "idx_pre_order_otps_analytics"
    t.index ["shop_id", "order_status", "created_at", "device_id"], name: "idx_pre_otps_covering_abandoned", where: "((cart_details IS NOT NULL) AND ((order_status)::text = 'AbandonedCheckout'::text))"
    t.index ["shop_id", "order_status", "created_at"], name: "idx_pre_otps_shop_status_created"
    t.index ["shop_id", "order_status"], name: "idx_pre_otps_with_cart_details", where: "(cart_details IS NOT NULL)"
    t.index ["shop_id", "status"], name: "idx_pre_order_otps_charging_queries", where: "(is_charged IS NULL)"
    t.index ["shop_id"], name: "index_pre_order_otps_on_shop_id"
    t.index ["ver_type"], name: "index_pre_order_otps_on_ver_type"
    t.index ["verification_status", "created_at"], name: "idx_pre_otps_verification", where: "((verification_status)::text = 'VERIFIED'::text)"
  end

  create_table "provinces", force: :cascade do |t|
    t.string "country_name"
    t.string "country_code"
    t.string "country_id"
    t.string "province_name"
    t.string "province_code"
    t.string "province_id"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rabbit_pay_configs", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.string "store_name"
    t.string "api_key", null: false
    t.string "api_secret", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "event_source_arn"
    t.text "domain_aliases"
    t.index ["shopify_domain"], name: "index_rabbit_pay_configs_on_shopify_domain", unique: true
  end

  create_table "rabbit_pay_merchants", force: :cascade do |t|
    t.string "email", null: false
    t.string "shopify_domain", null: false
    t.string "name"
    t.string "phone"
    t.string "privilege", default: "owner", null: false
    t.string "status", default: "active", null: false
    t.datetime "last_login_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_digest"
    t.index ["email", "shopify_domain"], name: "index_rabbit_pay_merchants_on_email_and_shopify_domain", unique: true
    t.index ["email"], name: "index_rabbit_pay_merchants_on_email"
    t.index ["shopify_domain"], name: "index_rabbit_pay_merchants_on_shopify_domain"
  end

  create_table "rabbit_pay_shops", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.string "access_token", null: false
    t.datetime "installed_at", null: false
    t.string "owner_email"
    t.string "owner_name"
    t.string "owner_phone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "welcome_email_sent_at"
    t.index ["shopify_domain"], name: "index_rabbit_pay_shops_on_shopify_domain", unique: true
  end

  create_table "rabbit_pay_wallet_topups", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.integer "amount_paise", null: false
    t.string "currency", default: "INR", null: false
    t.string "reference_id", null: false
    t.string "razorpay_payment_link_id"
    t.text "short_url"
    t.string "status", default: "pending", null: false
    t.string "razorpay_payment_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["razorpay_payment_id"], name: "index_rabbit_pay_wallet_topups_on_razorpay_payment_id", unique: true, where: "(razorpay_payment_id IS NOT NULL)"
    t.index ["razorpay_payment_link_id"], name: "index_rabbit_pay_wallet_topups_on_razorpay_payment_link_id"
    t.index ["reference_id"], name: "index_rabbit_pay_wallet_topups_on_reference_id", unique: true
    t.index ["shop_id"], name: "index_rabbit_pay_wallet_topups_on_shop_id"
  end

  create_table "redirects", force: :cascade do |t|
    t.string "path"
    t.string "target"
    t.bigint "shop_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "shopify_redirect_id"
    t.index ["shop_id"], name: "index_redirects_on_shop_id"
  end

  create_table "referral_earnings", force: :cascade do |t|
    t.bigint "referral_partner_id", null: false
    t.bigint "referral_shop_id", null: false
    t.string "transaction_type", null: false
    t.decimal "revenue_amount", precision: 10, scale: 2, null: false
    t.decimal "commission_rate", precision: 5, scale: 2, null: false
    t.decimal "commission_amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "USD"
    t.string "shopify_transaction_id"
    t.date "earning_date", null: false
    t.datetime "processed_at", default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "payout_status", default: "unpaid", null: false
    t.integer "payout_id"
    t.index ["payout_id"], name: "index_referral_earnings_on_payout_id"
    t.index ["payout_status"], name: "index_referral_earnings_on_payout_status"
    t.index ["referral_partner_id", "earning_date"], name: "index_referral_earnings_on_referral_partner_id_and_earning_date"
    t.index ["referral_partner_id"], name: "index_referral_earnings_on_referral_partner_id"
    t.index ["referral_shop_id", "earning_date"], name: "index_referral_earnings_on_referral_shop_id_and_earning_date"
    t.index ["referral_shop_id"], name: "index_referral_earnings_on_referral_shop_id"
    t.index ["shopify_transaction_id"], name: "index_referral_earnings_on_shopify_transaction_id", unique: true
  end

  create_table "referral_partners", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.decimal "subscription_commission_rate", precision: 5, scale: 2, default: "0.0"
    t.decimal "usage_commission_rate", precision: 5, scale: 2, default: "0.0"
    t.decimal "onetime_commission_rate", precision: 5, scale: 2, default: "0.0"
    t.boolean "active", default: true
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "account_type"
    t.string "bank_account_number"
    t.string "bank_ifsc_code"
    t.string "bank_account_name"
    t.string "bank_name"
    t.string "paypal_email"
    t.boolean "account_verified", default: false
    t.datetime "account_verified_at"
    t.string "phone"
    t.string "referral_code"
    t.index ["account_type"], name: "index_referral_partners_on_account_type"
    t.index ["account_verified"], name: "index_referral_partners_on_account_verified"
    t.index ["email"], name: "index_referral_partners_on_email", unique: true
    t.index ["referral_code"], name: "index_referral_partners_on_referral_code", unique: true
  end

  create_table "referral_shops", force: :cascade do |t|
    t.bigint "referral_partner_id", null: false
    t.string "shop_domain", null: false
    t.string "shopify_shop_id"
    t.boolean "active", default: true
    t.datetime "first_revenue_at"
    t.decimal "total_lifetime_revenue", precision: 10, scale: 2, default: "0.0"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "approved", default: false
    t.datetime "approved_at"
    t.string "approved_by"
    t.text "rejection_reason"
    t.boolean "historical_sync_completed", default: false
    t.date "historical_sync_from_date"
    t.date "last_sync_date"
    t.index ["approved"], name: "index_referral_shops_on_approved"
    t.index ["historical_sync_completed"], name: "index_referral_shops_on_historical_sync_completed"
    t.index ["referral_partner_id", "shop_domain"], name: "index_referral_shops_on_referral_partner_id_and_shop_domain", unique: true
    t.index ["referral_partner_id"], name: "index_referral_shops_on_referral_partner_id"
  end

  create_table "rto_order_events", force: :cascade do |t|
    t.bigint "shop_domain_id", null: false
    t.string "order_id", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at"
    t.string "source", default: "webhook", null: false
    t.string "webhook_id"
    t.jsonb "payload_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_rto_order_events_on_event_type"
    t.index ["occurred_at"], name: "index_rto_order_events_on_occurred_at"
    t.index ["shop_domain_id", "order_id"], name: "index_rto_order_events_on_shop_domain_id_and_order_id"
    t.index ["shop_domain_id"], name: "index_rto_order_events_on_shop_domain_id"
    t.index ["webhook_id"], name: "index_rto_order_events_on_webhook_id"
  end

  create_table "rto_orders", force: :cascade do |t|
    t.bigint "shop_domain_id", null: false
    t.string "order_id", null: false
    t.string "order_number"
    t.datetime "shopify_created_at"
    t.datetime "shopify_updated_at"
    t.datetime "processed_at"
    t.datetime "cancelled_at"
    t.datetime "closed_at"
    t.string "financial_status"
    t.string "fulfillment_status"
    t.boolean "is_cod", default: false, null: false
    t.decimal "total_price", precision: 12, scale: 2
    t.string "currency"
    t.string "gateway"
    t.string "zip"
    t.string "city"
    t.string "province"
    t.string "country"
    t.string "phone"
    t.string "phone_normalized"
    t.string "email"
    t.string "email_normalized"
    t.datetime "delivered_at"
    t.datetime "returned_at"
    t.datetime "rto_at"
    t.boolean "is_rto", default: false, null: false
    t.boolean "is_returned", default: false, null: false
    t.boolean "is_refunded", default: false, null: false
    t.decimal "refund_amount", precision: 12, scale: 2
    t.string "outcome_status"
    t.jsonb "tags", default: [], null: false
    t.jsonb "raw_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_fetched_at"
    t.index ["email_normalized"], name: "index_rto_orders_on_email_normalized"
    t.index ["last_fetched_at"], name: "index_rto_orders_on_last_fetched_at"
    t.index ["phone_normalized"], name: "index_rto_orders_on_phone_normalized"
    t.index ["shop_domain_id", "order_id"], name: "index_rto_orders_on_shop_domain_id_and_order_id", unique: true
    t.index ["shop_domain_id"], name: "index_rto_orders_on_shop_domain_id"
    t.index ["shopify_created_at"], name: "index_rto_orders_on_shopify_created_at"
    t.index ["shopify_updated_at"], name: "index_rto_orders_on_shopify_updated_at"
    t.index ["zip"], name: "index_rto_orders_on_zip"
  end

  create_table "scheduled_emails", force: :cascade do |t|
    t.bigint "email_rule_id", null: false
    t.bigint "shop_id"
    t.string "status", default: "pending", null: false
    t.datetime "scheduled_at"
    t.datetime "sent_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "uninstalled_shop_id"
    t.datetime "opened_at"
    t.string "open_tracking_token"
    t.datetime "send_job_enqueued_for"
    t.index ["email_rule_id", "shop_id"], name: "index_scheduled_emails_on_rule_and_shop_id", unique: true, where: "(shop_id IS NOT NULL)"
    t.index ["email_rule_id", "uninstalled_shop_id"], name: "index_scheduled_emails_on_rule_and_uninstalled_shop_id", unique: true, where: "(uninstalled_shop_id IS NOT NULL)"
    t.index ["email_rule_id"], name: "index_scheduled_emails_on_email_rule_id"
    t.index ["open_tracking_token"], name: "index_scheduled_emails_on_open_tracking_token", unique: true, where: "(open_tracking_token IS NOT NULL)"
    t.index ["shop_id"], name: "index_scheduled_emails_on_shop_id"
    t.index ["status", "created_at"], name: "index_scheduled_emails_on_status_and_created_at_desc", order: { created_at: :desc }
    t.index ["status"], name: "index_scheduled_emails_on_status"
  end

  create_table "scheduled_merchant_whatsapps", force: :cascade do |t|
    t.bigint "merchant_whatsapp_rule_id", null: false
    t.bigint "shop_id"
    t.bigint "uninstalled_shop_id"
    t.string "shopify_domain"
    t.string "status", default: "pending", null: false
    t.datetime "scheduled_at"
    t.datetime "sent_at"
    t.bigint "merchant_whatsapp_log_id"
    t.string "skip_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_whatsapp_rule_id", "shop_id"], name: "idx_sched_mwa_rule_shop", unique: true, where: "(shop_id IS NOT NULL)"
    t.index ["merchant_whatsapp_rule_id", "uninstalled_shop_id"], name: "idx_sched_mwa_rule_uninstalled", unique: true, where: "(uninstalled_shop_id IS NOT NULL)"
    t.index ["status", "scheduled_at"], name: "index_scheduled_merchant_whatsapps_on_status_and_scheduled_at"
  end

  create_table "scheduled_report_definitions", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", default: "", null: false
    t.string "output_format", default: "body_summary", null: false
    t.text "sql_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "merchant_description"
    t.jsonb "sql_metrics", default: [], null: false
    t.string "schedule_frequency", default: "daily", null: false
    t.text "email_body"
    t.boolean "default_subscribe_all", default: false, null: false
    t.integer "default_send_hour", default: 8, null: false
    t.integer "default_send_minute", default: 0, null: false
    t.integer "default_weekly_send_wday"
    t.index ["slug"], name: "index_scheduled_report_definitions_on_slug", unique: true
  end

  create_table "scheduled_report_deliveries", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "scheduled_shop_report_id", null: false
    t.bigint "scheduled_report_definition_id", null: false
    t.string "report_kind", default: "", null: false
    t.boolean "send_now", default: false, null: false
    t.datetime "sent_at"
    t.text "recipients"
    t.text "subject"
    t.string "status", default: "sent", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scheduled_report_definition_id"], name: "idx_on_scheduled_report_definition_id_4307704a16"
    t.index ["scheduled_shop_report_id"], name: "index_scheduled_report_deliveries_on_scheduled_shop_report_id"
    t.index ["sent_at", "report_kind"], name: "index_sched_report_deliveries_on_day_and_kind"
    t.index ["shop_id"], name: "index_scheduled_report_deliveries_on_shop_id"
    t.index ["status"], name: "index_scheduled_report_deliveries_on_status"
  end

  create_table "scheduled_shop_reports", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.boolean "enabled", default: false, null: false
    t.text "recipient_emails", default: "", null: false
    t.string "timezone", default: "", null: false
    t.date "last_sent_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "scheduled_report_definition_id", null: false
    t.integer "send_hour", default: 8, null: false
    t.integer "send_minute", default: 0, null: false
    t.integer "weekly_send_wday"
    t.datetime "explicit_opt_out_at"
    t.index ["enabled"], name: "index_scheduled_shop_reports_on_enabled"
    t.index ["scheduled_report_definition_id"], name: "index_scheduled_shop_reports_on_scheduled_report_definition_id"
    t.index ["shop_id", "scheduled_report_definition_id"], name: "index_shop_reports_shop_definition_unique", unique: true
    t.index ["shop_id"], name: "index_scheduled_shop_reports_on_shop_id"
  end

  create_table "session_recording_chunks", force: :cascade do |t|
    t.bigint "session_recording_id", null: false
    t.integer "seq", null: false
    t.integer "event_count", default: 0, null: false
    t.datetime "first_event_at"
    t.datetime "last_event_at"
    t.binary "payload", null: false
    t.datetime "created_at", null: false
    t.index ["session_recording_id", "seq"], name: "index_session_recording_chunks_on_session_recording_id_and_seq", unique: true
  end

  create_table "session_recordings", force: :cascade do |t|
    t.bigint "shop_id"
    t.string "shopify_domain", null: false
    t.string "session_key", null: false
    t.datetime "started_at", null: false
    t.datetime "last_event_at", null: false
    t.integer "duration_ms", default: 0, null: false
    t.integer "event_count", default: 0, null: false
    t.integer "chunk_count", default: 0, null: false
    t.bigint "compressed_bytes", default: 0, null: false
    t.string "entry_path"
    t.string "last_path"
    t.string "user_agent"
    t.integer "viewport_width"
    t.integer "viewport_height"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_event_at"], name: "index_session_recordings_on_last_event_at"
    t.index ["session_key"], name: "index_session_recordings_on_session_key", unique: true
    t.index ["shopify_domain", "started_at"], name: "index_session_recordings_on_shopify_domain_and_started_at"
    t.index ["started_at"], name: "index_session_recordings_on_started_at"
  end

  create_table "settings", force: :cascade do |t|
    t.boolean "status", default: false
    t.text "template"
    t.boolean "sms"
    t.boolean "whatsapp"
    t.boolean "ivr"
    t.bigint "shop_id"
    t.string "ivr_introduction"
    t.string "ivr_confirm_message"
    t.string "ivr_cancel_message"
    t.string "provider"
    t.text "provider_api_key"
    t.string "provider_sender_id"
    t.string "prepaid_template", default: "convert your order to prepaid by clicking the link. {{link}}"
    t.boolean "locked"
    t.text "otp_fallback_text"
    t.integer "otp_wait_time"
    t.integer "max_retries"
    t.boolean "auto_verify"
    t.boolean "show_cancel_button"
    t.string "dlt_template_id"
    t.string "dlt_bulk_template_id"
    t.boolean "cod_fee_enabled"
    t.decimal "cod_fees", default: "5.0"
    t.string "cod_label", default: "Cash on delivery fees"
    t.string "cod_description"
    t.string "cod_instrutction", default: "Please pay additional COD fees while collecting the delivery."
    t.boolean "is_checkout_done"
    t.integer "auto_cancel", default: -1
    t.boolean "is_shipping_phone_done"
    t.string "cod_variant_id"
    t.string "test_variant_id"
    t.string "test_order_url"
    t.boolean "is_cod_fee_checkout_done"
    t.boolean "is_cod_fee_email_done"
    t.integer "retry", default: -1
    t.string "retry_template"
    t.boolean "is_percentage"
    t.boolean "confirmation_sms_enabled"
    t.string "confirmation_flow_id"
    t.string "payment_provider"
    t.string "payment_provider_api_key"
    t.string "payment_provider_api_secret"
    t.boolean "prepaid_enabled"
    t.integer "prepaid_expiry", default: 1440
    t.float "prepaid_discount"
    t.string "thankyou_message"
    t.float "transaction_fee", default: 1.0
    t.boolean "whatsapp_enabled", default: true
    t.string "cancel_template", default: "Order placed on {{store_url}} is canceled. Reason - Phone number not verified. Visit {{store_url}} to place a new order."
    t.boolean "cancel_notif_enabled", default: false
    t.string "include_countries"
    t.string "custom_script"
    t.boolean "auto_delete"
    t.string "payment_customization_id"
    t.string "payment_method_name"
    t.decimal "min_cart_total"
    t.decimal "max_cart_total"
    t.boolean "abandoned_cart_enabled"
    t.string "abandoned_template", default: "We notice you left these items in your cart. Complete your checkout now. Check it here {{a_url}}"
    t.decimal "shipping_cost", default: "1.0"
    t.string "hide_delivery_method", default: ""
    t.string "selected_countries", default: ""
    t.string "selected_zips", default: ""
    t.string "selected_product_ids", default: ""
    t.boolean "enable_pre_order_otp", default: false
    t.string "country_code_list", default: ""
    t.string "phone_numbers", default: ""
    t.string "excluded_zips", default: ""
    t.string "pre_heading", default: "Login/Signup to Checkout"
    t.string "pre_sub_heading", default: "Confirm your mobile number to proceed to checkout"
    t.string "pre_send_button_label", default: "Send Code"
    t.string "pre_verify_button_label", default: "Verify Code"
    t.string "pre_invalid_otp_msg", default: "Invalid OTP"
    t.string "pre_success_message", default: "Phone number verified - Proceed to checkout"
    t.string "pre_skip_btn_text"
    t.string "order_confirmation_template"
    t.string "pre_redirect_text"
    t.boolean "pre_show_skip_btn", default: false
    t.boolean "enable_fulfilment_message", default: false
    t.string "fulfilment_template", default: ""
    t.string "prepaid_amount_type", default: "FULL"
    t.decimal "prepaid_token_amount", default: "0.0"
    t.string "prepaid_discount_type", default: "FLAT"
    t.string "prepaid_heading", default: "Convert your COD order to Prepaid to get ₹150 off and Faster delivery."
    t.string "prepaid_sub_heading", default: "Pay now to save money and get delivery faster."
    t.boolean "prepaid_notif", default: true
    t.string "pre_primary_button_color", default: "#000000"
    t.string "pre_secondary_button_color", default: "#000000"
    t.string "pre_primary_button_font_color", default: "#FFFFFF"
    t.string "pre_secondary_button_font_color", default: "#FFFFFF"
    t.boolean "skip_draft_order", default: true
    t.boolean "ac_whatsapp", default: false
    t.string "excluded_shipping_methods", default: ""
    t.boolean "pre_whatsapp_button", default: false
    t.text "pre_whatsapp_button_text", default: "Send Code to Whatsapp"
    t.string "ac_whatsapp_schedule", default: "0"
    t.string "ac_sms_schedule", default: "0"
    t.string "hide_provinces", default: ""
    t.string "show_provinces", default: ""
    t.boolean "debug", default: false
    t.string "sender", default: ""
    t.string "fulfilment_flow_id", default: ""
    t.string "cod_fee_shipping_keyword", default: ""
    t.boolean "enable_shipping_cod_fees", default: false
    t.string "hide_product_variant_ids", default: ""
    t.boolean "confirmation_whatsapp", default: false
    t.boolean "fulfilment_whatsapp", default: false
    t.string "order_number_prefix", default: ""
    t.boolean "lock_paid_feature", default: false
    t.string "ac_whatsapp_discount", default: ""
    t.string "ac_whatsapp_discount_code", default: ""
    t.boolean "ac_whatsapp_discout_enabled", default: false
    t.string "retry_flow_id", default: ""
    t.string "cancel_flow_id", default: ""
    t.string "ac_flow_id", default: ""
    t.string "order_number_suffix", default: ""
    t.string "prepaid_banner_color", default: "#FFE477"
    t.string "whatsapp_approval_status", default: "send_request", null: false
    t.string "whatsapp_approval_notes"
    t.string "branded_whatsapp_number", default: ""
    t.boolean "only_send_confirmation_to_cod", default: false
    t.string "prepaid_schedule", default: ""
    t.string "post_order_include_product_ids", default: ""
    t.string "otp_ext_heading", default: "Verify OTP for faster delivery"
    t.string "otp_ext_enter_otp_sent_on", default: "Please enter the OTP sent on"
    t.string "otp_ext_sending_otp", default: "Sending OTP to your mobile number..."
    t.string "otp_ext_enter_otp", default: "Enter OTP"
    t.string "otp_ext_resend_otp_in", default: "Resend OTP in"
    t.string "otp_ext_resend_otp", default: "Resend OTP"
    t.string "otp_ext_get_code_in_whatsapp", default: "Get code on WhatsApp"
    t.string "otp_ext_verify_otp", default: "Verify OTP"
    t.string "otp_ext_successful", default: "OTP Verification Successful!"
    t.string "otp_ext_change", default: "change"
    t.string "otp_ext_submit", default: "submit"
    t.boolean "first_purchase_whatsapp_enabled", default: false
    t.string "first_purchase_schedule", default: ""
    t.string "first_purchase_discount_code", default: ""
    t.string "first_purchase_discount_off", default: ""
    t.string "whatsapp_operator_config", default: ""
    t.string "show_product_ids", default: ""
    t.string "delivery_customization_id", default: ""
    t.boolean "hide_shipping_method", default: false
    t.boolean "is_prefilled_address_enabled", default: false
    t.string "pre_phone_placeholder", default: "Phone"
    t.string "pre_invalid_phone", default: "Please enter a valid 10-digit phone number."
    t.string "pre_verify_mobile", default: "Verify Mobile Number"
    t.string "pre_enter_code", default: "Enter the code sent to"
    t.string "pre_retry_in", default: "Didnt receive the Code? Retry in"
    t.string "pre_resend", default: "Resend"
    t.string "pre_failed_to_verify", default: "Failed to verify OTP. Please try again."
    t.string "pre_verifying", default: "Verifying"
    t.string "pre_too_many", default: "Too many attemps. Please select other payment options."
    t.boolean "pre_is_new_design_enabled", default: false
    t.string "pre_v2_title", default: ""
    t.string "store_front_token", default: ""
    t.boolean "pre_is_login_enabled", default: false
    t.string "pre_v2_theme", default: "theme5"
    t.boolean "pre_v2_show_order_summary", default: false
    t.boolean "partial_payment_enabled", default: false
    t.boolean "is_tax_included_with_product", default: false
    t.string "pre_block_phone", default: ""
    t.decimal "hide_discount_total"
    t.string "email_addresses"
    t.boolean "hide_gift_cards", default: false
    t.string "hide_vendors"
    t.string "show_vendors"
    t.string "selected_locale", default: ""
    t.boolean "pre_email_mandatory", default: false
    t.string "partial_shipping_keyword", default: ""
    t.string "pre_geo_countries", default: ""
    t.string "excluded_collection_ids", default: ""
    t.string "selected_collection_ids", default: ""
    t.boolean "pre_show_branding", default: true
    t.string "partial_payment_flow", default: "SAME_ORDER"
    t.boolean "pre_v2_show_send_code", default: true
    t.string "pre_v2_partial_tax_text", default: "Taxes computed later"
    t.decimal "partial_transaction_fee", default: "0.0"
    t.jsonb "abandoned_cart_configs", default: []
    t.boolean "send_verification_link_only", default: false
    t.boolean "post_send_only_whatsapp", default: false
    t.integer "variant_pick_condition", default: 0
    t.string "whatsapp_language_code", default: "en", null: false
    t.string "brand_logo_url", default: ""
    t.boolean "quick_onboarding_visited"
    t.string "user_journey"
    t.integer "pre_v2_overwrite_popup_condition", default: 0
    t.string "pre_v2_cart_drawer_layout_selectors", default: ""
    t.datetime "last_callback_request_at"
    t.integer "callback_requests_count", default: 0
    t.integer "partial_payment_flow_version", default: 1
    t.string "cart_transform_id"
    t.string "verification_tag", default: "✅ COD-Verified", null: false
    t.string "whatsapp_order_confirmation_template"
    t.datetime "last_whatsapp_integration_request_at"
    t.integer "whatsapp_integration_requests_count", default: 0
    t.integer "web_ux_version", default: 2
    t.string "partial_dummy_variant_id"
    t.string "partial_discount_automatic_app_gid"
    t.boolean "promo_banner_show", default: true
    t.string "promo_banner_text", default: ""
    t.string "promo_banner_color", default: ""
    t.string "promo_text_color", default: ""
    t.string "whatsapp_first_purchase_template"
    t.string "whatsapp_abandoned_cart_template"
    t.string "whatsapp_fulfilment_template"
    t.string "whatsapp_cod_verification_template"
    t.datetime "metafield_settings_refreshed_at"
    t.jsonb "private_payment_provider"
    t.boolean "cod_form_enabled", default: false, null: false
    t.boolean "pre_v2_show_tax_info", default: false, null: false
    t.string "pixel_id"
    t.string "pixel_token"
    t.string "pixel_test_event_id"
    t.boolean "persistent_signin", default: false, null: false
    t.string "google_conversion_token"
    t.boolean "show_offer_and_reward", default: false, null: false
    t.boolean "pre_v2_show_shipping_info", default: false, null: false
    t.boolean "hide_for_unverified_orders", default: false, null: false
    t.string "google_conversion_id"
    t.string "google_conversion_label"
    t.boolean "pixel_enabled", default: false, null: false
    t.boolean "google_analytics_enabled", default: true, null: false
    t.boolean "third_party_checkout", default: false, null: false
    t.string "pre_v2_no_rule_qualified_message", default: "", null: false
    t.boolean "plus_checkout_otp_extension_enabled", default: false, null: false
    t.boolean "cod_form_v2", default: false, null: false
    t.boolean "show_qr_option", default: true
    t.jsonb "third_party_payment_method_rules", default: {}, null: false
    t.boolean "revert_discount", default: false, null: false
    t.datetime "lightweight_settings_changed_at"
    t.boolean "conversion_tracking", default: true, null: false
    t.string "whatsapp_pre_verify_otp_template"
    t.string "whatsapp_prepaid_template_name", default: "order_tracking_new", null: false
    t.jsonb "prepaid_reminders", default: [], null: false
    t.boolean "partial_expand_flow_enabled", default: false, null: false
    t.integer "omit_whatsapp_message_ttl", default: 0, null: false
    t.string "cod_only_shipping_keyword", default: ""
    t.bigint "bsp_prepaid_template_id"
    t.boolean "optimized_buy_now", default: false, null: false
    t.jsonb "cod_form_config", default: {}, null: false
    t.jsonb "ui_customization", default: {}, null: false
    t.boolean "partial_discount_combines_with_order", default: false, null: false
    t.boolean "partial_discount_combines_with_product", default: false, null: false
    t.boolean "partial_discount_combines_with_shipping", default: false, null: false
    t.boolean "include_shipping_in_payment_options", default: false, null: false
    t.boolean "meta_events_enabled", default: false
    t.string "pre_proceed_button_label", default: "Proceed to Payment"
    t.index ["lightweight_settings_changed_at"], name: "index_settings_on_lightweight_settings_changed_at"
    t.index ["shop_id"], name: "index_settings_on_shop_id"
  end

  create_table "settings_change_audits", force: :cascade do |t|
    t.bigint "shop_id"
    t.string "field", null: false
    t.string "old_value"
    t.string "new_value"
    t.datetime "changed_at", null: false
    t.string "changed_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["field", "changed_at"], name: "index_settings_change_audits_on_field_and_changed_at"
    t.index ["shop_id", "changed_at"], name: "index_settings_change_audits_on_shop_id_and_changed_at"
  end

  create_table "shop_activity_dailies", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.date "activity_date", null: false
    t.integer "orders", default: 0
    t.integer "sms_sent", default: 0
    t.integer "whatsapp_sent", default: 0
    t.integer "otp_completions", default: 0
    t.integer "partial_payments", default: 0
    t.datetime "last_order_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_date"], name: "index_shop_activity_dailies_on_activity_date"
    t.index ["shop_id", "activity_date"], name: "index_shop_activity_dailies_on_shop_id_and_activity_date", unique: true
  end

  create_table "shop_charge_overrides", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.decimal "whatsapp_utility_multiplier", precision: 8, scale: 4
    t.decimal "whatsapp_marketing_multiplier", precision: 8, scale: 4
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "whatsapp_bsp_commission_usd", precision: 10, scale: 6
    t.index ["shop_id"], name: "index_shop_charge_overrides_on_shop_id", unique: true
  end

  create_table "shop_domains", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.datetime "last_seen_at"
    t.jsonb "backfill_state", default: {}, null: false
    t.datetime "backfill_started_at"
    t.datetime "backfill_completed_at"
    t.datetime "last_reconciled_at"
    t.datetime "last_webhook_received_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "backfill_last_attempt_at"
    t.datetime "backfill_next_retry_at"
    t.text "backfill_last_error", default: ""
    t.datetime "incremental_sync_cursor_at"
    t.index ["backfill_last_attempt_at"], name: "index_shop_domains_on_backfill_last_attempt_at"
    t.index ["backfill_next_retry_at"], name: "index_shop_domains_on_backfill_next_retry_at"
    t.index ["incremental_sync_cursor_at"], name: "index_shop_domains_on_incremental_sync_cursor_at"
    t.index ["shopify_domain"], name: "index_shop_domains_on_shopify_domain", unique: true
  end

  create_table "shop_installations", force: :cascade do |t|
    t.bigint "shop_domain_id", null: false
    t.bigint "shop_id"
    t.string "status", default: "installed", null: false
    t.string "scopes", default: ""
    t.string "access_token"
    t.datetime "installed_at"
    t.datetime "uninstalled_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_domain_id", "status"], name: "index_shop_installations_on_shop_domain_id_and_status"
    t.index ["shop_domain_id"], name: "index_shop_installations_on_shop_domain_id"
    t.index ["shop_id"], name: "index_shop_installations_on_shop_id"
  end

  create_table "shops", force: :cascade do |t|
    t.string "shopify_domain", null: false
    t.string "shopify_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "customer_email"
    t.string "owner_email"
    t.string "owner_name"
    t.string "primary_locale"
    t.string "owner_phone"
    t.string "country_name"
    t.string "owner_timezone"
    t.string "shop_owner"
    t.bigint "plan_id"
    t.string "charge_id"
    t.float "sms_charge", default: 0.02
    t.float "ivr_charge", default: 0.04
    t.integer "test_notif_count", default: 0
    t.string "country_code"
    t.string "money_format"
    t.string "currency"
    t.integer "max_orders"
    t.string "visible_plans"
    t.boolean "reviewed"
    t.string "phone_pick_order"
    t.text "cod_include_tags"
    t.text "cod_exclude_tags"
    t.string "primary_domain"
    t.decimal "risk_level"
    t.string "shopify_plan"
    t.decimal "charge_multiplier", default: "0.0"
    t.integer "reminder_count", default: 0
    t.string "shop_created_date"
    t.string "relationship_manager", default: ""
    t.datetime "initial_customer_pull_completed", precision: nil
    t.datetime "partial_rule_sets_metafield_synced_at"
    t.integer "customer_count"
    t.datetime "rabbit_pay_welcome_email_sent_at"
    t.datetime "last_shipping_status_pulled"
    t.datetime "installed_at"
    t.string "rabbit_pay_token"
    t.datetime "rabbit_pay_installed_at"
    t.decimal "rabbit_pay_wallet_balance", precision: 12, scale: 2, default: "0.0", null: false
    t.string "shopify_refresh_token"
    t.datetime "shopify_token_expires_at"
    t.datetime "shopify_refresh_token_expires_at"
    t.datetime "shopify_token_refreshed_at"
    t.datetime "first_order_at"
    t.datetime "last_order_at"
    t.datetime "last_active_at"
    t.datetime "onboarding_completed_at"
    t.string "acquisition_source"
    t.integer "churn_risk_score"
    t.string "churn_risk_band"
    t.string "churn_risk_primary_factor"
    t.string "churn_risk_action"
    t.jsonb "churn_risk_reasons", default: []
    t.datetime "churn_risk_computed_at"
    t.string "otp_campaign_coupon_code"
    t.datetime "otp_campaign_coupon_applied_at"
    t.string "source", default: "shopify", null: false
    t.index ["churn_risk_band", "churn_risk_score"], name: "index_shops_on_churn_risk_band_and_churn_risk_score"
    t.index ["created_at"], name: "idx_shops_created_at"
    t.index ["id", "currency"], name: "idx_shops_currency_lookup"
    t.index ["last_active_at"], name: "index_shops_on_last_active_at"
    t.index ["last_shipping_status_pulled"], name: "index_shops_on_last_shipping_status_pulled"
    t.index ["plan_id"], name: "index_shops_on_plan_id"
    t.index ["shopify_domain"], name: "index_shops_on_shopify_domain", unique: true
    t.index ["source"], name: "index_shops_on_source"
  end

  create_table "sidekiq_jobs", force: :cascade do |t|
    t.string "jid"
    t.string "queue"
    t.string "class_name"
    t.text "args"
    t.boolean "retry"
    t.datetime "enqueued_at", precision: nil
    t.datetime "started_at", precision: nil
    t.datetime "finished_at", precision: nil
    t.string "status"
    t.string "name"
    t.text "result"
    t.index ["class_name"], name: "index_sidekiq_jobs_on_class_name"
    t.index ["enqueued_at"], name: "index_sidekiq_jobs_on_enqueued_at"
    t.index ["finished_at"], name: "index_sidekiq_jobs_on_finished_at"
    t.index ["jid"], name: "index_sidekiq_jobs_on_jid"
    t.index ["queue"], name: "index_sidekiq_jobs_on_queue"
    t.index ["retry"], name: "index_sidekiq_jobs_on_retry"
    t.index ["started_at"], name: "index_sidekiq_jobs_on_started_at"
    t.index ["status"], name: "index_sidekiq_jobs_on_status"
  end

  create_table "sms_provider_country_mappings", force: :cascade do |t|
    t.string "provider", null: false
    t.text "supported_countries", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_sms_provider_country_mappings_on_provider", unique: true
  end

  create_table "sms_template_approvals", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "setting_id", null: false
    t.string "template_type_key", null: false
    t.string "target_column", null: false
    t.text "body", null: false
    t.jsonb "variables_used", default: [], null: false
    t.integer "max_variables", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.string "submitted_by"
    t.datetime "submitted_at", null: false
    t.string "reviewed_by"
    t.datetime "reviewed_at"
    t.text "review_reason"
    t.datetime "applied_to_settings_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["setting_id"], name: "index_sms_template_approvals_on_setting_id"
    t.index ["shop_id", "template_type_key", "status"], name: "idx_sms_template_approvals_shop_type_status"
    t.index ["shop_id"], name: "index_sms_template_approvals_on_shop_id"
    t.index ["status"], name: "index_sms_template_approvals_on_status"
  end

  create_table "sms_template_type_configs", force: :cascade do |t|
    t.string "key", null: false
    t.string "display_name", null: false
    t.string "target_column", null: false
    t.jsonb "allowed_variables", default: [], null: false
    t.integer "max_variables", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_sms_template_type_configs_on_active"
    t.index ["key"], name: "index_sms_template_type_configs_on_key", unique: true
  end

  create_table "sms_templates", force: :cascade do |t|
    t.string "template_name"
    t.string "message_type"
    t.string "sender_id"
    t.string "country_codes"
    t.string "template_body"
    t.string "template_example"
    t.string "dlt_template_id"
    t.string "status"
    t.bigint "shop_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_sms_templates_on_shop_id"
  end

  create_table "sso_sessions", force: :cascade do |t|
    t.string "session_token", null: false
    t.string "phone", null: false
    t.string "country_code"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_sso_sessions_on_expires_at"
    t.index ["phone"], name: "index_sso_sessions_on_phone"
    t.index ["session_token"], name: "index_sso_sessions_on_session_token", unique: true
  end

  create_table "sso_tokens", force: :cascade do |t|
    t.string "token", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "browser_id"
    t.index ["browser_id"], name: "index_sso_tokens_on_browser_id", where: "(browser_id IS NOT NULL)"
    t.index ["expires_at"], name: "index_sso_tokens_on_expires_at"
    t.index ["token"], name: "index_sso_tokens_on_token", unique: true
  end

  create_table "summary_snapshots", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.integer "window_days", default: 30, null: false
    t.jsonb "payload", default: {}
    t.datetime "computed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "window_days"], name: "index_summary_snapshots_on_shop_id_and_window_days", unique: true
    t.index ["shop_id"], name: "index_summary_snapshots_on_shop_id"
  end

  create_table "support_lead_trackings", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "assigned_engineer"
    t.boolean "activated", default: false, null: false
    t.boolean "verified_setup", default: false, null: false
    t.boolean "contacted", default: false, null: false
    t.boolean "reminder_1_sent", default: false, null: false
    t.boolean "reminder_2_sent", default: false, null: false
    t.boolean "reminder_3_sent", default: false, null: false
    t.boolean "not_interested", default: false, null: false
    t.boolean "onboarded_to_free_plan", default: false, null: false
    t.boolean "onboarded_to_paid_plan", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "closed_at"
    t.text "comment"
    t.index ["closed_at"], name: "index_support_lead_trackings_on_closed_at"
    t.index ["shop_id"], name: "index_support_lead_trackings_on_shop_id", unique: true
  end

  create_table "tracking_pixels", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "platform", null: false
    t.string "pixel_id", null: false
    t.text "access_token"
    t.jsonb "config", default: {}, null: false
    t.jsonb "targeting", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "platform", "enabled"], name: "index_tracking_pixels_on_shop_id_and_platform_and_enabled"
    t.index ["shop_id", "platform", "pixel_id"], name: "index_tracking_pixels_on_shop_id_and_platform_and_pixel_id", unique: true
  end

  create_table "twilio_logs", force: :cascade do |t|
    t.string "sid"
    t.string "ver_type"
    t.string "country_code"
    t.string "customer_number"
    t.boolean "is_charged", default: false
    t.string "status"
    t.bigint "order_confirmation_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "num_segment"
    t.decimal "actual_charge_applied", precision: 8, scale: 4, default: "0.0"
    t.index ["order_confirmation_id"], name: "index_twilio_logs_on_order_confirmation_id"
    t.index ["shop_id", "created_at", "status"], name: "idx_twilio_status_analytics"
    t.index ["shop_id", "created_at", "ver_type", "status"], name: "idx_twilio_logs_communication_analytics"
    t.index ["shop_id", "is_charged", "status", "ver_type"], name: "idx_twilio_logs_charging_queries"
    t.index ["shop_id"], name: "index_twilio_logs_on_shop_id"
  end

  create_table "twilio_pricings", force: :cascade do |t|
    t.string "country_code"
    t.string "country"
    t.string "sms_price"
    t.datetime "created_at", precision: nil
    t.datetime "updated_at", precision: nil
    t.string "whatsapp"
    t.decimal "bsp_whatsapp", precision: 10, scale: 4, default: "0.003", null: false
    t.decimal "whatsapp_utility", precision: 10, scale: 4
    t.decimal "whatsapp_marketing", precision: 10, scale: 4
  end

  create_table "uninstalled_shops", force: :cascade do |t|
    t.integer "shop_id"
    t.string "shop_domain"
    t.string "email"
    t.string "phone"
    t.string "shopify_created_date"
    t.string "owner_name"
    t.string "order_count"
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "shopify_created_on", default: ""
    t.boolean "sms", default: false
    t.boolean "confirmation_sms_enabled", default: false
    t.boolean "cod_fee_enabled", default: false
    t.boolean "enable_pre_order_otp", default: false
    t.boolean "abandoned_cart_enabled", default: false
    t.boolean "prepaid_enabled", default: false
    t.string "notes", default: ""
    t.integer "customer_count"
    t.boolean "partial_payment_enabled", default: false
    t.boolean "ac_whatsapp", default: false
    t.boolean "bsp_integrated", default: false
    t.boolean "cod_show_hide_enabled", default: false
    t.string "uninstall_reason"
    t.text "uninstall_feedback"
    t.string "survey_token"
    t.datetime "first_order_at"
    t.datetime "last_order_at"
    t.datetime "last_active_at"
    t.string "plan_name_at_uninstall"
    t.integer "tenure_days"
    t.integer "orders_last_30d"
    t.integer "churn_risk_at_uninstall"
    t.string "churn_risk_band_at_uninstall"
    t.jsonb "feature_snapshot", default: {}, null: false
    t.datetime "survey_submitted_at"
    t.jsonb "survey_responses", default: {}, null: false
    t.index ["created_at"], name: "idx_uninstalled_shops_created_at"
    t.index ["shop_domain"], name: "index_uninstalled_shops_on_shop_domain"
    t.index ["survey_submitted_at"], name: "index_uninstalled_shops_on_survey_submitted_at"
    t.index ["survey_token"], name: "index_uninstalled_shops_on_survey_token", unique: true
  end

  create_table "unsubscribed_emails", force: :cascade do |t|
    t.string "email"
    t.string "source"
    t.datetime "unsubscribed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "wallets", force: :cascade do |t|
    t.decimal "total_balance", precision: 10, scale: 2, default: "1.0", null: false
    t.decimal "balance_used", precision: 10, scale: 2, default: "0.0", null: false
    t.string "shopify_domain", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_domain"], name: "index_wallets_on_shopify_domain", unique: true
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "provider", null: false
    t.string "endpoint_token", null: false
    t.text "secret"
    t.string "signature_scheme", default: "shared_secret", null: false
    t.string "signature_header", default: "X-Webhook-Signature", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "event_config", default: {}, null: false
    t.jsonb "stats", default: {}, null: false
    t.boolean "mirror_to_slack", default: false, null: false
    t.datetime "last_received_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint_token"], name: "index_webhook_endpoints_on_endpoint_token", unique: true
    t.index ["shop_id", "provider"], name: "idx_webhook_endpoints_unique_per_shop_provider", unique: true
    t.index ["shop_id"], name: "index_webhook_endpoints_on_shop_id"
  end

  create_table "whatsapp_accounts", force: :cascade do |t|
    t.bigint "shop_id"
    t.string "waba_id"
    t.string "business_account_id"
    t.string "phone_number_id"
    t.string "display_phone_number"
    t.string "verified_name"
    t.string "quality_rating"
    t.text "system_user_token"
    t.datetime "token_expires_at"
    t.integer "status", default: 0, null: false
    t.datetime "webhook_subscribed_at"
    t.datetime "last_synced_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "registered_at"
    t.boolean "is_default", default: false, null: false
    t.string "label"
    t.text "registration_pin"
    t.bigint "custom_branded_client_id"
    t.string "messaging_limit_tier"
    t.datetime "quality_updated_at"
    t.string "previous_quality_rating"
    t.index ["custom_branded_client_id"], name: "index_whatsapp_accounts_on_cb_client_id"
    t.index ["phone_number_id"], name: "index_whatsapp_accounts_on_phone_number_id"
    t.index ["shop_id"], name: "index_whatsapp_accounts_on_shop_id"
    t.index ["status"], name: "index_whatsapp_accounts_on_status"
    t.index ["waba_id"], name: "index_whatsapp_accounts_on_waba_id"
  end

  create_table "whatsapp_ai_credit_transactions", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "kind", null: false
    t.string "status", default: "completed", null: false
    t.integer "credits", default: 0, null: false
    t.integer "balance_after"
    t.string "pack"
    t.decimal "amount_usd", precision: 10, scale: 2
    t.string "shopify_charge_gid"
    t.text "confirmation_url"
    t.bigint "whatsapp_ai_run_id"
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "created_at"], name: "idx_wa_ai_tx_shop_time"
    t.index ["shop_id", "status"], name: "idx_wa_ai_tx_pending", where: "((status)::text = 'pending'::text)"
    t.index ["shopify_charge_gid"], name: "idx_wa_ai_tx_charge", unique: true, where: "(shopify_charge_gid IS NOT NULL)"
  end

  create_table "whatsapp_ai_runs", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "whatsapp_conversation_id"
    t.bigint "trigger_message_id"
    t.bigint "reply_message_id"
    t.string "mode", null: false
    t.string "outcome", null: false
    t.string "intent"
    t.text "reply_text"
    t.string "handoff_reason"
    t.jsonb "actions", default: [], null: false
    t.integer "credits_charged", default: 0, null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "cached_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.decimal "cost_usd", precision: 10, scale: 6, default: "0.0", null: false
    t.string "model"
    t.integer "latency_ms"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "created_at"], name: "idx_wa_ai_runs_shop_time"
    t.index ["whatsapp_conversation_id", "created_at"], name: "idx_wa_ai_runs_conversation"
  end

  create_table "whatsapp_ai_settings", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "reply_mode", default: 0, null: false
    t.string "agent_name"
    t.string "tone", default: "friendly", null: false
    t.jsonb "skills", default: {}, null: false
    t.jsonb "discount", default: {}, null: false
    t.boolean "allow_cancel", default: false, null: false
    t.text "knowledge"
    t.text "handoff_text"
    t.jsonb "test_numbers", default: [], null: false
    t.datetime "went_live_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "team_timeout_minutes", default: 30, null: false
    t.integer "daily_reply_limit", default: 40, null: false
    t.index ["shop_id"], name: "index_whatsapp_ai_settings_on_shop_id", unique: true
  end

  create_table "whatsapp_ai_wallets", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.integer "balance", default: 0, null: false
    t.integer "lifetime_purchased", default: 0, null: false
    t.integer "lifetime_used", default: 0, null: false
    t.datetime "free_granted_at"
    t.boolean "auto_recharge", default: false, null: false
    t.string "auto_recharge_pack"
    t.datetime "auto_recharge_failed_at"
    t.string "auto_recharge_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_whatsapp_ai_wallets_on_shop_id", unique: true
  end

  create_table "whatsapp_audience_imports", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "status", default: "uploaded", null: false
    t.jsonb "columns", default: []
    t.integer "row_count", default: 0
    t.integer "valid_count", default: 0
    t.string "phone_column"
    t.string "name_column"
    t.string "email_column"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "raw_content"
    t.index ["shop_id"], name: "index_whatsapp_audience_imports_on_shop_id"
  end

  create_table "whatsapp_campaign_recipients", force: :cascade do |t|
    t.bigint "whatsapp_campaign_id", null: false
    t.bigint "shop_id", null: false
    t.string "phone", null: false
    t.string "name"
    t.string "email"
    t.string "source_ref"
    t.jsonb "fields", default: {}
    t.string "status", default: "pending", null: false
    t.string "suppression_reason"
    t.string "meta_message_id"
    t.string "error_code"
    t.text "error_message"
    t.bigint "whatsapp_message_log_id"
    t.datetime "queued_at"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "read_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "attempt_count", default: 0, null: false
    t.datetime "next_retry_at"
    t.datetime "last_attempt_at"
    t.index ["meta_message_id"], name: "index_whatsapp_campaign_recipients_on_meta_message_id"
    t.index ["shop_id", "phone", "sent_at"], name: "idx_wa_campaign_recipients_shop_phone_sent", where: "(sent_at IS NOT NULL)"
    t.index ["status", "next_retry_at"], name: "idx_wa_campaign_recipients_retry", where: "((status)::text = 'retry_pending'::text)"
    t.index ["whatsapp_campaign_id", "last_attempt_at"], name: "idx_wa_campaign_recipients_campaign_last_attempt", where: "(last_attempt_at IS NOT NULL)"
    t.index ["whatsapp_campaign_id", "phone"], name: "idx_on_whatsapp_campaign_id_phone_66adb63cc6", unique: true
    t.index ["whatsapp_campaign_id", "status"], name: "idx_on_whatsapp_campaign_id_status_f15515cb59"
  end

  create_table "whatsapp_campaigns", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "whatsapp_account_id"
    t.bigint "whatsapp_template_id"
    t.bigint "whatsapp_audience_import_id"
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "draft", null: false
    t.string "audience_source"
    t.jsonb "audience_filter", default: {}
    t.jsonb "variable_mapping", default: {}
    t.string "button_field"
    t.string "header_field"
    t.jsonb "discount_config"
    t.integer "rate_per_minute", default: 600
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "audience_count", default: 0
    t.integer "suppressed_count", default: 0
    t.integer "queued_count", default: 0
    t.integer "sent_count", default: 0
    t.integer "delivered_count", default: 0
    t.integer "read_count", default: 0
    t.integer "failed_count", default: 0
    t.integer "replied_count", default: 0
    t.decimal "estimated_cost", precision: 12, scale: 2, default: "0.0"
    t.string "currency"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variable_defaults", default: {}
    t.string "missing_value_policy", default: "default", null: false
    t.text "last_error"
    t.jsonb "retry_config", default: {}
    t.bigint "whatsapp_segment_id"
    t.string "recipe_key"
    t.jsonb "send_policy", default: {}, null: false
    t.string "pause_reason"
    t.jsonb "pause_detail", default: {}, null: false
    t.datetime "paused_at"
    t.datetime "guardrail_notified_at"
    t.index ["scheduled_at"], name: "index_whatsapp_campaigns_on_scheduled_at"
    t.index ["shop_id", "status"], name: "index_whatsapp_campaigns_on_shop_id_and_status"
  end

  create_table "whatsapp_contacts", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "phone", null: false
    t.string "name"
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.string "source", default: "manual", null: false
    t.jsonb "tags", default: [], null: false
    t.jsonb "attrs", default: {}, null: false
    t.boolean "subscribed", default: true, null: false
    t.integer "order_count", default: 0
    t.decimal "total_spent", precision: 12, scale: 2, default: "0.0"
    t.datetime "last_order_at"
    t.string "source_ref"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "cod_orders_count", default: 0, null: false
    t.integer "prepaid_orders_count", default: 0, null: false
    t.integer "rto_orders_count", default: 0, null: false
    t.integer "returned_orders_count", default: 0, null: false
    t.datetime "last_cod_order_at"
    t.datetime "last_unconfirmed_cod_at"
    t.datetime "order_stats_synced_at"
    t.index ["shop_id", "created_at"], name: "index_whatsapp_contacts_on_shop_id_and_created_at"
    t.index ["shop_id", "phone"], name: "index_whatsapp_contacts_on_shop_id_and_phone", unique: true
    t.index ["tags"], name: "index_whatsapp_contacts_on_tags", using: :gin
  end

  create_table "whatsapp_conversation_episodes", force: :cascade do |t|
    t.bigint "whatsapp_conversation_id", null: false
    t.bigint "shop_id", null: false
    t.datetime "opened_at", null: false
    t.datetime "first_response_at"
    t.bigint "first_response_agent_id"
    t.datetime "resolved_at"
    t.string "resolved_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "opened_at"], name: "idx_wa_conv_episodes_opened"
    t.index ["shop_id", "resolved_at"], name: "idx_wa_conv_episodes_resolved", where: "(resolved_at IS NOT NULL)"
    t.index ["whatsapp_conversation_id", "opened_at"], name: "idx_wa_conv_episodes_conversation"
  end

  create_table "whatsapp_conversation_labels", force: :cascade do |t|
    t.bigint "whatsapp_conversation_id", null: false
    t.bigint "whatsapp_inbox_label_id", null: false
    t.bigint "shop_id", null: false
    t.string "source", default: "agent", null: false
    t.datetime "created_at", null: false
    t.index ["shop_id", "whatsapp_inbox_label_id"], name: "idx_wa_conv_labels_filter"
    t.index ["whatsapp_conversation_id", "whatsapp_inbox_label_id"], name: "idx_wa_conv_labels_unique", unique: true
  end

  create_table "whatsapp_conversation_messages", force: :cascade do |t|
    t.bigint "whatsapp_conversation_id", null: false
    t.bigint "shop_id", null: false
    t.integer "direction", null: false
    t.string "source", null: false
    t.string "kind", null: false
    t.text "body"
    t.jsonb "content", default: {}, null: false
    t.string "meta_message_id"
    t.string "reply_to_meta_message_id"
    t.bigint "whatsapp_inbound_message_id"
    t.bigint "whatsapp_message_log_id"
    t.bigint "agent_id"
    t.integer "status"
    t.string "error_code"
    t.text "error_message"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "read_at"
    t.datetime "failed_at"
    t.string "media_id"
    t.string "media_mime_type"
    t.string "media_file_name"
    t.bigint "media_size"
    t.string "media_sha256"
    t.integer "media_state", default: 0, null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["meta_message_id"], name: "idx_wa_conv_msgs_meta_id", unique: true, where: "(meta_message_id IS NOT NULL)"
    t.index ["occurred_at"], name: "idx_wa_conv_msgs_media_retention", where: "(media_state = 2)"
    t.index ["shop_id", "agent_id", "created_at"], name: "idx_wa_conv_msgs_agent_replies", where: "(agent_id IS NOT NULL)"
    t.index ["whatsapp_conversation_id", "occurred_at", "id"], name: "idx_wa_conv_msgs_thread"
    t.index ["whatsapp_conversation_id", "updated_at"], name: "idx_wa_conv_msgs_poll"
    t.index ["whatsapp_inbound_message_id"], name: "idx_wa_conv_msgs_inbound", unique: true, where: "(whatsapp_inbound_message_id IS NOT NULL)"
    t.index ["whatsapp_message_log_id"], name: "idx_wa_conv_msgs_log", unique: true, where: "(whatsapp_message_log_id IS NOT NULL)"
  end

  create_table "whatsapp_conversations", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "whatsapp_account_id"
    t.string "customer_wa_id", null: false
    t.string "phone_last10", null: false
    t.string "customer_name"
    t.integer "status", default: 0, null: false
    t.datetime "status_changed_at", null: false
    t.bigint "assignee_agent_id"
    t.integer "unread_count", default: 0, null: false
    t.datetime "last_inbound_at", null: false
    t.string "last_inbound_meta_message_id"
    t.string "read_receipt_meta_message_id"
    t.datetime "last_message_at", null: false
    t.string "last_message_preview", limit: 200
    t.integer "last_message_direction", default: 0, null: false
    t.datetime "last_agent_reply_at"
    t.datetime "last_auto_reply_at"
    t.bigint "current_episode_id"
    t.text "note"
    t.datetime "unanswered_alert_sent_at"
    t.datetime "window_closed_hint_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "ai_paused_until"
    t.datetime "ai_handoff_at"
    t.text "ai_draft"
    t.datetime "ai_draft_at"
    t.bigint "ai_last_message_id"
    t.jsonb "ai_discount"
    t.index ["shop_id", "assignee_agent_id", "status"], name: "idx_wa_conversations_assignee"
    t.index ["shop_id", "customer_wa_id"], name: "idx_wa_conversations_orphans", where: "(whatsapp_account_id IS NULL)"
    t.index ["shop_id", "last_inbound_at"], name: "idx_wa_conversations_shop_inbound", order: { last_inbound_at: :desc }
    t.index ["shop_id", "phone_last10"], name: "idx_wa_conversations_shop_last10"
    t.index ["shop_id", "status", "last_inbound_at"], name: "idx_wa_conversations_shop_status_inbound", order: { last_inbound_at: :desc }
    t.index ["shop_id"], name: "idx_wa_conversations_unread", where: "(unread_count > 0)"
    t.index ["status_changed_at"], name: "idx_wa_conversations_pending_age", where: "(status = 1)"
    t.index ["whatsapp_account_id", "customer_wa_id"], name: "idx_wa_conversations_account_wa_id", unique: true
    t.index ["whatsapp_account_id", "phone_last10"], name: "idx_wa_conversations_account_last10"
  end

  create_table "whatsapp_country_languages", force: :cascade do |t|
    t.string "country_code", null: false
    t.string "language", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_whatsapp_country_languages_on_country_code", unique: true
  end

  create_table "whatsapp_inbound_messages", force: :cascade do |t|
    t.bigint "shop_id"
    t.bigint "whatsapp_account_id"
    t.bigint "whatsapp_message_log_id"
    t.string "meta_message_id", null: false
    t.string "parent_meta_message_id"
    t.string "from_phone", null: false
    t.string "kind", null: false
    t.string "payload"
    t.text "display_text"
    t.datetime "received_at", null: false
    t.jsonb "meta_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "custom_branded_client_id"
    t.index ["custom_branded_client_id"], name: "index_whatsapp_inbound_messages_on_cb_client_id"
    t.index ["meta_message_id"], name: "index_whatsapp_inbound_messages_on_meta_message_id", unique: true
    t.index ["parent_meta_message_id"], name: "index_whatsapp_inbound_messages_on_parent_meta_message_id"
    t.index ["shop_id", "received_at"], name: "index_whatsapp_inbound_messages_on_shop_id_and_received_at", order: { received_at: :desc }
    t.index ["shop_id"], name: "index_whatsapp_inbound_messages_on_shop_id"
    t.index ["whatsapp_account_id"], name: "index_whatsapp_inbound_messages_on_whatsapp_account_id"
    t.index ["whatsapp_message_log_id"], name: "index_whatsapp_inbound_messages_on_whatsapp_message_log_id"
  end

  create_table "whatsapp_inbox_agents", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "shopify_user_id", default: 0, null: false
    t.string "name"
    t.string "email"
    t.boolean "account_owner", default: false, null: false
    t.datetime "last_seen_at"
    t.datetime "profile_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "shopify_user_id"], name: "index_whatsapp_inbox_agents_on_shop_id_and_shopify_user_id", unique: true
  end

  create_table "whatsapp_inbox_labels", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "name", limit: 40, null: false
    t.string "color", default: "info", null: false
    t.string "system_key"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "shop_id, lower((name)::text)", name: "idx_wa_inbox_labels_name", unique: true
    t.index ["shop_id", "system_key"], name: "index_whatsapp_inbox_labels_on_shop_id_and_system_key", unique: true, where: "(system_key IS NOT NULL)"
  end

  create_table "whatsapp_inbox_settings", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.boolean "read_receipts", default: true, null: false
    t.boolean "auto_label", default: true, null: false
    t.boolean "welcome_enabled", default: false, null: false
    t.text "welcome_text"
    t.boolean "away_enabled", default: false, null: false
    t.text "away_text"
    t.jsonb "business_hours", default: {}, null: false
    t.jsonb "keyword_rules", default: [], null: false
    t.boolean "unanswered_email_enabled", default: false, null: false
    t.integer "unanswered_email_minutes", default: 30, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_whatsapp_inbox_settings_on_shop_id", unique: true
  end

  create_table "whatsapp_link_clicks", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "event_type_key", null: false
    t.string "source_external_id"
    t.integer "stage_index", default: 0, null: false
    t.string "recipient_last10"
    t.string "destination_host"
    t.datetime "clicked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "event_type_key", "clicked_at"], name: "idx_wa_link_clicks_shop_event_time"
    t.index ["shop_id", "event_type_key", "source_external_id", "stage_index"], name: "idx_wa_link_clicks_send"
  end

  create_table "whatsapp_message_logs", force: :cascade do |t|
    t.bigint "shop_id"
    t.bigint "whatsapp_account_id"
    t.bigint "whatsapp_template_id"
    t.string "event_type_key", null: false
    t.string "template_name"
    t.string "recipient", null: false
    t.string "meta_message_id"
    t.integer "status", default: 0, null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "read_at"
    t.datetime "failed_at"
    t.jsonb "payload_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "country_code"
    t.boolean "is_charged", default: false, null: false
    t.decimal "actual_charge_applied", precision: 10, scale: 4
    t.integer "stage_index"
    t.string "source_external_id"
    t.bigint "whatsapp_campaign_id"
    t.bigint "whatsapp_campaign_recipient_id"
    t.bigint "custom_branded_client_id"
    t.index "whatsapp_account_id, \"right\"(regexp_replace((recipient)::text, '\\D'::text, ''::text, 'g'::text), 10), created_at", name: "idx_wa_logs_account_recipient_last10"
    t.index ["custom_branded_client_id", "event_type_key", "source_external_id", "stage_index"], name: "idx_whatsapp_logs_unique_per_send_cb", unique: true, where: "((custom_branded_client_id IS NOT NULL) AND (source_external_id IS NOT NULL) AND (status <> 4))"
    t.index ["custom_branded_client_id"], name: "index_whatsapp_message_logs_on_cb_client_id"
    t.index ["event_type_key"], name: "index_whatsapp_message_logs_on_event_type_key"
    t.index ["meta_message_id"], name: "index_whatsapp_message_logs_on_meta_message_id"
    t.index ["shop_id", "event_type_key", "source_external_id", "stage_index"], name: "idx_whatsapp_logs_dedup"
    t.index ["shop_id", "event_type_key", "source_external_id", "stage_index"], name: "idx_whatsapp_logs_unique_per_send", unique: true, where: "((source_external_id IS NOT NULL) AND (status <> 4))"
    t.index ["shop_id", "is_charged", "status"], name: "idx_whatsapp_logs_billing"
    t.index ["shop_id", "status", "created_at"], name: "idx_whatsapp_logs_shop_status_time"
    t.index ["shop_id"], name: "index_whatsapp_message_logs_on_shop_id"
    t.index ["whatsapp_account_id"], name: "index_whatsapp_message_logs_on_whatsapp_account_id"
    t.index ["whatsapp_campaign_id"], name: "index_whatsapp_message_logs_on_whatsapp_campaign_id"
    t.index ["whatsapp_template_id"], name: "index_whatsapp_message_logs_on_whatsapp_template_id"
  end

  create_table "whatsapp_number_integration_requests", force: :cascade do |t|
    t.string "shop_domain", null: false
    t.string "email", null: false
    t.string "phone_number", null: false
    t.string "preferred_time"
    t.string "status", default: "pending"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_domain", "created_at"], name: "idx_on_shop_domain_created_at_9642d319b4"
    t.index ["shop_domain"], name: "index_whatsapp_number_integration_requests_on_shop_domain"
    t.index ["status"], name: "index_whatsapp_number_integration_requests_on_status"
  end

  create_table "whatsapp_opt_outs", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "phone_normalized", null: false
    t.string "reason"
    t.string "source"
    t.datetime "opted_out_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "phone_normalized"], name: "index_whatsapp_opt_outs_on_shop_id_and_phone_normalized", unique: true
  end

  create_table "whatsapp_order_attributions", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "order_id", null: false
    t.bigint "order_confirmation_id"
    t.string "order_name"
    t.decimal "order_total", precision: 12, scale: 2, default: "0.0", null: false
    t.string "currency"
    t.boolean "is_cod", default: false, null: false
    t.datetime "ordered_at", null: false
    t.string "attribution_type", null: false
    t.string "event_type_key", null: false
    t.bigint "whatsapp_campaign_id"
    t.bigint "whatsapp_message_log_id"
    t.datetime "touch_at", null: false
    t.string "phone_last10", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "event_type_key", "ordered_at"], name: "idx_wa_order_attributions_event_time"
    t.index ["shop_id", "order_id", "attribution_type"], name: "idx_wa_order_attributions_unique", unique: true
    t.index ["shop_id", "whatsapp_campaign_id"], name: "idx_wa_order_attributions_campaign"
  end

  create_table "whatsapp_reattempts", force: :cascade do |t|
    t.string "flow", null: false
    t.string "source_type", null: false
    t.bigint "source_id", null: false
    t.bigint "shop_id"
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "first_failed_at", null: false
    t.datetime "next_retry_at"
    t.datetime "finished_at"
    t.string "provider_message_id"
    t.string "error_code"
    t.text "error_message"
    t.string "drop_reason"
    t.jsonb "request", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_message_id"], name: "index_whatsapp_reattempts_on_provider_message_id"
    t.index ["shop_id", "created_at"], name: "index_whatsapp_reattempts_on_shop_id_and_created_at"
    t.index ["source_type", "source_id"], name: "index_whatsapp_reattempts_on_source_type_and_source_id", unique: true
    t.index ["status", "next_retry_at"], name: "index_whatsapp_reattempts_on_status_and_next_retry_at"
  end

  create_table "whatsapp_saved_replies", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "title", limit: 60, null: false
    t.string "shortcut", limit: 30, null: false
    t.text "body", null: false
    t.integer "usage_count", default: 0, null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "shop_id, lower((shortcut)::text)", name: "idx_wa_saved_replies_shortcut", unique: true
  end

  create_table "whatsapp_segments", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.string "name", null: false
    t.text "description"
    t.jsonb "filters", default: {}, null: false
    t.integer "cached_count", default: 0
    t.datetime "counted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_whatsapp_segments_on_shop_id"
  end

  create_table "whatsapp_template_bindings", force: :cascade do |t|
    t.bigint "shop_id", null: false
    t.bigint "whatsapp_template_id", null: false
    t.string "event_type_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "offset_minutes", default: 0, null: false
    t.integer "stage_index", default: 0, null: false
    t.jsonb "discount_config", default: {}, null: false
    t.bigint "whatsapp_account_id"
    t.datetime "paused_at"
    t.datetime "resumed_at"
    t.datetime "last_paused_at"
    t.index ["shop_id", "event_type_key", "stage_index"], name: "idx_whatsapp_bindings_unique_per_event_stage", unique: true
    t.index ["shop_id"], name: "index_whatsapp_template_bindings_on_shop_id"
    t.index ["whatsapp_account_id"], name: "index_whatsapp_template_bindings_on_whatsapp_account_id"
    t.index ["whatsapp_template_id"], name: "index_whatsapp_template_bindings_on_whatsapp_template_id"
  end

  create_table "whatsapp_template_translations", force: :cascade do |t|
    t.string "template_name", null: false
    t.string "language", null: false
    t.string "category"
    t.string "status", default: "not_started", null: false
    t.jsonb "source_components", default: [], null: false
    t.jsonb "components", default: [], null: false
    t.string "drafted_by"
    t.string "submitted_by"
    t.text "rejection_reason"
    t.jsonb "last_msg91_response", default: {}, null: false
    t.datetime "submitted_at"
    t.datetime "approved_at"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["language", "status"], name: "index_wa_template_translations_on_language_and_status"
    t.index ["template_name", "language"], name: "index_wa_template_translations_on_name_and_language", unique: true
  end

  create_table "whatsapp_templates", force: :cascade do |t|
    t.bigint "whatsapp_account_id", null: false
    t.string "meta_template_id"
    t.string "name", null: false
    t.string "language", default: "en_US", null: false
    t.string "category", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "components", default: [], null: false
    t.string "rejection_reason"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "event_type_key"
    t.jsonb "variable_mapping", default: {}, null: false
    t.jsonb "url_button"
    t.jsonb "header_media"
    t.index ["event_type_key"], name: "index_whatsapp_templates_on_event_type_key"
    t.index ["meta_template_id"], name: "index_whatsapp_templates_on_meta_template_id"
    t.index ["status"], name: "index_whatsapp_templates_on_status"
    t.index ["whatsapp_account_id", "name", "language"], name: "idx_whatsapp_templates_uniqueness", unique: true
    t.index ["whatsapp_account_id"], name: "index_whatsapp_templates_on_whatsapp_account_id"
  end

  create_table "win_back_outreaches", force: :cascade do |t|
    t.bigint "shop_id"
    t.string "shopify_domain"
    t.string "trigger", null: false
    t.string "channel"
    t.string "status", default: "pending"
    t.datetime "sent_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "trigger"], name: "index_win_back_outreaches_on_shop_id_and_trigger"
    t.index ["shopify_domain"], name: "index_win_back_outreaches_on_shopify_domain"
  end

  add_foreign_key "abandon_cart_schedules", "shops"
  add_foreign_key "abandoned_carts", "shops"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "backfill_leases", "shop_domains"
  add_foreign_key "branded_whatsapp_templates", "shops"
  add_foreign_key "checkout_sessions", "shops", on_delete: :cascade
  add_foreign_key "checkout_sessions", "sso_tokens"
  add_foreign_key "country_plan_offer_redemptions", "country_plan_offers"
  add_foreign_key "custom_branded_api_keys", "custom_branded_clients"
  add_foreign_key "custom_branded_template_events", "custom_branded_clients"
  add_foreign_key "custom_branded_template_events", "whatsapp_templates", on_delete: :cascade
  add_foreign_key "custom_branded_webhook_deliveries", "custom_branded_clients"
  add_foreign_key "customer_addresses", "customers"
  add_foreign_key "customer_pull_job_queues", "shops"
  add_foreign_key "customer_shop_mappings", "customers"
  add_foreign_key "customer_sync_states", "shops"
  add_foreign_key "discounts", "shops"
  add_foreign_key "email_click_redirects", "scheduled_emails"
  add_foreign_key "email_rules", "email_templates"
  add_foreign_key "follow_up_comments", "follow_ups"
  add_foreign_key "follow_ups", "shops"
  add_foreign_key "follow_ups", "uninstalled_shops", on_delete: :cascade, validate: false
  add_foreign_key "global_customer_stats", "customer_identities"
  add_foreign_key "headers", "shops"
  add_foreign_key "inbound_webhook_events", "shops", on_delete: :cascade
  add_foreign_key "inbound_webhook_events", "webhook_endpoints", on_delete: :nullify
  add_foreign_key "integrations", "shops"
  add_foreign_key "notification_logs", "shops"
  add_foreign_key "onboarding_events", "shops", on_delete: :nullify
  add_foreign_key "order_confirmations", "shops"
  add_foreign_key "partial_rule_sets", "shops"
  add_foreign_key "payment_reconciliations", "shops"
  add_foreign_key "payout_earnings", "payouts"
  add_foreign_key "payout_earnings", "referral_earnings"
  add_foreign_key "payouts", "referral_partners"
  add_foreign_key "pre_order_otps", "shops"
  add_foreign_key "rabbit_pay_wallet_topups", "shops"
  add_foreign_key "redirects", "shops"
  add_foreign_key "referral_earnings", "payouts", on_delete: :nullify
  add_foreign_key "referral_earnings", "referral_partners"
  add_foreign_key "referral_earnings", "referral_shops"
  add_foreign_key "referral_shops", "referral_partners"
  add_foreign_key "rto_order_events", "shop_domains"
  add_foreign_key "rto_orders", "shop_domains"
  add_foreign_key "scheduled_emails", "email_rules"
  add_foreign_key "scheduled_emails", "shops"
  add_foreign_key "scheduled_report_deliveries", "scheduled_report_definitions"
  add_foreign_key "scheduled_report_deliveries", "scheduled_shop_reports"
  add_foreign_key "scheduled_report_deliveries", "shops", on_delete: :cascade
  add_foreign_key "scheduled_shop_reports", "scheduled_report_definitions"
  add_foreign_key "scheduled_shop_reports", "shops", on_delete: :cascade
  add_foreign_key "session_recording_chunks", "session_recordings", on_delete: :cascade
  add_foreign_key "settings", "shops", on_delete: :cascade
  add_foreign_key "shop_installations", "shop_domains"
  add_foreign_key "shops", "plans"
  add_foreign_key "sms_template_approvals", "settings", on_delete: :cascade
  add_foreign_key "sms_template_approvals", "shops"
  add_foreign_key "sms_templates", "shops"
  add_foreign_key "support_lead_trackings", "shops"
  add_foreign_key "twilio_logs", "order_confirmations"
  add_foreign_key "twilio_logs", "shops"
  add_foreign_key "webhook_endpoints", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_accounts", "custom_branded_clients", validate: false
  add_foreign_key "whatsapp_accounts", "shops"
  add_foreign_key "whatsapp_ai_credit_transactions", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_ai_runs", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_ai_settings", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_ai_wallets", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_conversation_episodes", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_conversation_episodes", "whatsapp_conversations", on_delete: :cascade
  add_foreign_key "whatsapp_conversation_episodes", "whatsapp_inbox_agents", column: "first_response_agent_id", on_delete: :nullify
  add_foreign_key "whatsapp_conversation_labels", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_conversation_labels", "whatsapp_conversations", on_delete: :cascade
  add_foreign_key "whatsapp_conversation_labels", "whatsapp_inbox_labels", on_delete: :cascade
  add_foreign_key "whatsapp_conversation_messages", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_conversation_messages", "whatsapp_conversations", on_delete: :cascade
  add_foreign_key "whatsapp_conversation_messages", "whatsapp_inbound_messages", on_delete: :nullify
  add_foreign_key "whatsapp_conversation_messages", "whatsapp_inbox_agents", column: "agent_id", on_delete: :nullify
  add_foreign_key "whatsapp_conversation_messages", "whatsapp_message_logs", on_delete: :nullify
  add_foreign_key "whatsapp_conversations", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_conversations", "whatsapp_accounts", on_delete: :nullify
  add_foreign_key "whatsapp_conversations", "whatsapp_inbox_agents", column: "assignee_agent_id", on_delete: :nullify
  add_foreign_key "whatsapp_inbound_messages", "custom_branded_clients", validate: false
  add_foreign_key "whatsapp_inbound_messages", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_inbound_messages", "whatsapp_accounts", on_delete: :nullify
  add_foreign_key "whatsapp_inbound_messages", "whatsapp_message_logs", on_delete: :nullify
  add_foreign_key "whatsapp_inbox_agents", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_inbox_labels", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_inbox_settings", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_message_logs", "custom_branded_clients", validate: false
  add_foreign_key "whatsapp_message_logs", "shops"
  add_foreign_key "whatsapp_message_logs", "whatsapp_accounts", on_delete: :nullify
  add_foreign_key "whatsapp_message_logs", "whatsapp_templates", on_delete: :nullify
  add_foreign_key "whatsapp_saved_replies", "shops", on_delete: :cascade
  add_foreign_key "whatsapp_template_bindings", "shops"
  add_foreign_key "whatsapp_template_bindings", "whatsapp_accounts", on_delete: :nullify
  add_foreign_key "whatsapp_template_bindings", "whatsapp_templates"
  add_foreign_key "whatsapp_templates", "whatsapp_accounts"
end
