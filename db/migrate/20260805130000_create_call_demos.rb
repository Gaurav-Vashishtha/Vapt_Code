# frozen_string_literal: true

class CreateCallDemos < ActiveRecord::Migration[7.2]
  def up
    create_table :call_demos do |t|
      t.string :shopify_domain, null: false
      t.bigint :shop_id
      t.datetime :scheduled_at
      t.string :owner
      t.string :status, null: false, default: "scheduled"
      t.text :notes
      t.string :created_by
      t.bigint :source_call_record_id
      t.timestamps
    end
    add_index :call_demos, [:status, :scheduled_at], name: "index_call_demos_on_status_and_scheduled_at"
    add_index :call_demos, :shopify_domain, name: "index_call_demos_on_shopify_domain"

    # Backfill: seed one demo per existing "demo_scheduled" call record so the
    # Demos tab keeps its history. Owner defaults to whoever logged the call.
    execute(<<~SQL)
      INSERT INTO call_demos
        (shopify_domain, shop_id, scheduled_at, owner, status, notes, source_call_record_id, created_by, created_at, updated_at)
      SELECT shopify_domain, shop_id,
             NULLIF(metadata->>'demo_at', '')::timestamptz,
             agent_name, 'scheduled', notes, id, agent_name, called_at, now()
      FROM call_records
      WHERE outcome = 'demo_scheduled'
    SQL
  end

  def down
    drop_table :call_demos
  end
end
