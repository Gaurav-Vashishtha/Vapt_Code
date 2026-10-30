class AddNameToAbandonedCart < ActiveRecord::Migration[6.0]
  def change
    add_column :abandoned_carts, :name, :string, default:''
  end
end
