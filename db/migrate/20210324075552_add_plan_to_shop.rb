class AddPlanToShop < ActiveRecord::Migration[6.0]
  def change
    add_reference :shops, :plan, null: true, foreign_key: true
    add_column :shops, :charge_id, :string
  end
end
