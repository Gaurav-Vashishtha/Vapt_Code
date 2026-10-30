class AddEventTypeToWhatsappTemplatesAndCreateBindings < ActiveRecord::Migration[7.2]
  def change
    add_column :whatsapp_templates, :event_type_key, :string
    add_column :whatsapp_templates, :variable_mapping, :jsonb, default: {}, null: false
    add_index :whatsapp_templates, :event_type_key

    create_table :whatsapp_template_bindings do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :whatsapp_template, null: false, foreign_key: true
      t.string :event_type_key, null: false
      t.timestamps
    end

    # At most one active template per (shop, event_type). Swapping = upsert.
    add_index :whatsapp_template_bindings,
              [:shop_id, :event_type_key],
              unique: true,
              name: 'idx_whatsapp_bindings_unique_per_event'
  end
end
