class CreateAbandonCartSchedule < ActiveRecord::Migration[6.0]
  def change
    create_table :abandon_cart_schedules do |t|
      t.string :cart_id,null: false
      t.boolean :is_sheduled
      t.integer :schedule_count
      t.references :shop, foreign_key: true
      t.timestamps
    end
  end
end
