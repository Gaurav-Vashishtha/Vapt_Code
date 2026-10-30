class CreateFormFunnelEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :form_funnel_events do |t|
      t.bigint   :shop_id, null: false
      t.string   :session_token
      t.string   :event_type, null: false
      t.datetime :occurred_at, null: false
      t.jsonb    :metadata, default: {}
      t.timestamps
    end

    add_index :form_funnel_events, :shop_id
    add_index :form_funnel_events, :session_token
    add_index :form_funnel_events, %i[shop_id event_type occurred_at]
    add_index :form_funnel_events, %i[shop_id session_token]
  end
end
