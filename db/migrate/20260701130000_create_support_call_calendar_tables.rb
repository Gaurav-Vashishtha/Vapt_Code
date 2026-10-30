# frozen_string_literal: true

class CreateSupportCallCalendarTables < ActiveRecord::Migration[7.2]
  def change
    create_table :call_targets do |t|
      t.date :call_date, null: false
      t.string :shopify_domain, null: false
      t.bigint :shop_id
      t.string :segment, null: false
      t.integer :rank
      t.integer :cps, default: 0
      t.integer :value_score, default: 0
      t.integer :urgency_score, default: 0
      t.jsonb :reasons, default: []
      t.string :assigned_engineer
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
    add_index :call_targets, %i[call_date shopify_domain], unique: true
    add_index :call_targets, %i[call_date status]
    add_index :call_targets, %i[call_date rank]

    create_table :call_records do |t|
      t.string :shopify_domain, null: false
      t.bigint :shop_id
      t.bigint :call_target_id
      t.string :segment
      t.string :outcome, null: false
      t.string :agent_name
      t.text :notes
      t.integer :cps_at_call
      t.datetime :called_at, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index :call_records, %i[shopify_domain called_at]
    add_index :call_records, :called_at
    add_index :call_records, :call_target_id

    create_table :call_reminders do |t|
      t.string :shopify_domain, null: false
      t.bigint :shop_id
      t.date :due_on, null: false
      t.text :note
      t.string :created_by
      t.string :status, null: false, default: "open"
      t.bigint :source_call_record_id
      t.timestamps
    end
    add_index :call_reminders, %i[status due_on]
    add_index :call_reminders, %i[shopify_domain status]

    create_table :call_events do |t|
      t.string :shopify_domain, null: false
      t.bigint :shop_id
      t.string :event_type, null: false
      t.string :agent_name
      t.jsonb :payload, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :call_events, %i[shopify_domain occurred_at]

    create_table :call_suppressions do |t|
      t.string :shopify_domain, null: false
      t.string :reason, null: false
      t.date :until_on
      t.string :created_by
      t.timestamps
    end
    add_index :call_suppressions, :shopify_domain, unique: true
  end
end
