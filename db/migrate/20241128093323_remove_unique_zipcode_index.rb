class RemoveUniqueZipcodeIndex < ActiveRecord::Migration[6.0]
  def change
    remove_index :locations, :zipcode
  end
end
