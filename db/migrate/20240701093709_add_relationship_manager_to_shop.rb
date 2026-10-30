class AddRelationshipManagerToShop < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :relationship_manager, :string, default: ''
  end
end
