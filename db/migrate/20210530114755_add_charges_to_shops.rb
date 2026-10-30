class AddChargesToShops < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :sms_charge, :float, default: 0.02
    add_column :shops, :ivr_charge, :float, default: 0.04
  end
end
