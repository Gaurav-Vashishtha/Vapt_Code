class AddVisiblePlansToShops < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :visible_plans, :string
  end
end
