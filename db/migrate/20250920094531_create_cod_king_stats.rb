# db/migrate/create_cod_king_stats.rb
class CreateCodKingStats < ActiveRecord::Migration[7.0]
  def change
    create_table :cod_king_stats do |t|
      t.string :stat_key, null: false, index: true
      t.integer :stat_value, null: false, default: 0
      t.date :stat_date, null: false, index: true
      t.text :description
      
      t.timestamps
      
      # Composite index for efficient lookups by key and date
      t.index [:stat_key, :stat_date], unique: true, name: 'index_cod_king_stats_on_key_and_date'
    end
  end
end