class AddRiskLevelToShops < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :risk_level, :decimal
  end
end
