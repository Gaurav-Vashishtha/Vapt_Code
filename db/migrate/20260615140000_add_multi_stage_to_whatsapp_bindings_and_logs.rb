class AddMultiStageToWhatsappBindingsAndLogs < ActiveRecord::Migration[7.2]
  # Extends the binding model so one event (abandoned_cart) can have many
  # active bindings — one per reminder stage — each with its own template
  # and discount config. Adds the dedup columns on message logs needed for
  # the cron scheduler to know which stage went out for which checkout.
  def change
    # ── Bindings: per-stage template + discount ─────────────────────────
    add_column :whatsapp_template_bindings, :stage_index,     :integer, null: false, default: 0
    add_column :whatsapp_template_bindings, :discount_config, :jsonb,   null: false, default: {}

    # Drop the (shop_id, event_type_key) UNIQUE — multiple stages per event
    # are now legal — and add a tighter one that includes the stage index so
    # we still prevent accidental dupes within a stage.
    remove_index :whatsapp_template_bindings, name: 'idx_whatsapp_bindings_unique_per_event'
    add_index :whatsapp_template_bindings,
              [:shop_id, :event_type_key, :stage_index],
              unique: true,
              name: 'idx_whatsapp_bindings_unique_per_event_stage'

    # ── Logs: which stage went out, and which source object it points to ──
    # source_external_id is the Shopify checkout token (for abandoned_cart)
    # or order id (for order_* events). Lets the scheduler answer
    # "did we send stage N for this checkout already?" without scanning the
    # JSONB payload_snapshot.
    add_column :whatsapp_message_logs, :stage_index,        :integer
    add_column :whatsapp_message_logs, :source_external_id, :string

    add_index :whatsapp_message_logs,
              [:shop_id, :event_type_key, :source_external_id, :stage_index],
              name: 'idx_whatsapp_logs_dedup'
  end
end
