class AddUniqueIndexToLocks < ActiveRecord::Migration[6.0]
  def change
  	add_index :locks, :value, unique: true
  end
end
