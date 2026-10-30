# frozen_string_literal: true

class CreateWhatsappLinkClicks < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_link_clicks do |t|
      t.references :shop, null: false, index: false
      t.string :event_type_key, null: false
      t.string :source_external_id
      t.integer :stage_index, null: false, default: 0
      t.string :recipient_last10
      t.string :destination_host
      t.datetime :clicked_at, null: false
      t.timestamps
    end
    add_index :whatsapp_link_clicks, %i[shop_id event_type_key clicked_at], name: 'idx_wa_link_clicks_shop_event_time'
    add_index :whatsapp_link_clicks, %i[shop_id event_type_key source_external_id stage_index], name: 'idx_wa_link_clicks_send'
  end
end
