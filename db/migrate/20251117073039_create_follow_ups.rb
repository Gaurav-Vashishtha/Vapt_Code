class CreateFollowUps < ActiveRecord::Migration[7.2]
  def change
    create_table :follow_ups do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :source_tab, null: false
      t.text :notes, null: false
      t.string :status, null: false, default: "pending"
      t.text :resolved_notes
      t.datetime :resolved_at
      t.string :resolved_by
      t.string :resolved_source_tab

      t.timestamps
    end

    add_index :follow_ups, :status
  end
end
