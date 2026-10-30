class RemoveProblematicAbandonedCartsIndex < ActiveRecord::Migration[7.2]
  def change
    remove_index :abandoned_carts, name: "idx_abandoned_carts_communication", if_exists: true
  end
end