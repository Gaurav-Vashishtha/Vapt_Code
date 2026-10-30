class CreateLocationsTable < ActiveRecord::Migration[6.0]
   def change
    create_table :locations do |t|
      t.string :country
      t.string :zipcode
      t.string :province
      t.string :city

      t.timestamps
    end
    add_index :locations, :zipcode, unique: true
  end
end
