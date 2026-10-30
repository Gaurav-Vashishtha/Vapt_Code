class CreateCustomBrandedTemplateEvents < ActiveRecord::Migration[7.2]
  def change
    return if table_exists?(:custom_branded_template_events)

    create_table :custom_branded_template_events do |t|
      t.references :custom_branded_client, null: false, foreign_key: true, index: false
      t.references :whatsapp_template, null: false,
                   foreign_key: { on_delete: :cascade },
                   index: { unique: true, name: 'index_cb_template_events_on_template_id' }
      t.string :event_id, null: false
      t.string :event_name
      t.string :event_group
      t.jsonb :variables, default: [], null: false
      t.jsonb :button_variables, default: {}, null: false
      t.boolean :active, default: false, null: false
      t.timestamps
    end

    add_index :custom_branded_template_events,
              %i[custom_branded_client_id event_id],
              name: 'index_cb_template_events_on_client_and_event'

    add_index :custom_branded_template_events,
              %i[custom_branded_client_id event_id],
              unique: true,
              where: 'active',
              name: 'index_cb_template_events_one_active_per_event'
  end
end
