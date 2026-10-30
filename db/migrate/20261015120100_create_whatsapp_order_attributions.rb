# frozen_string_literal: true

class CreateWhatsappOrderAttributions < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    with_lock_retries do
      create_table :whatsapp_order_attributions do |t|
        t.bigint :shop_id, null: false
        t.string :order_id, null: false
        t.bigint :order_confirmation_id
        t.string :order_name
        t.decimal :order_total, precision: 12, scale: 2, default: 0, null: false
        t.string :currency
        t.boolean :is_cod, default: false, null: false
        t.datetime :ordered_at, null: false
        t.string :attribution_type, null: false
        t.string :event_type_key, null: false
        t.bigint :whatsapp_campaign_id
        t.bigint :whatsapp_message_log_id
        t.datetime :touch_at, null: false
        t.string :phone_last10, null: false
        t.timestamps
      end
      add_index :whatsapp_order_attributions, %i[shop_id order_id attribution_type], unique: true,
                name: "idx_wa_order_attributions_unique"
      add_index :whatsapp_order_attributions, %i[shop_id whatsapp_campaign_id],
                name: "idx_wa_order_attributions_campaign"
      add_index :whatsapp_order_attributions, %i[shop_id event_type_key ordered_at],
                name: "idx_wa_order_attributions_event_time"
    end
  end
end
