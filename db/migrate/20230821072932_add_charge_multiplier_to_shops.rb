class AddChargeMultiplierToShops < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :charge_multiplier, :decimal, default: 0.0
  end
end
