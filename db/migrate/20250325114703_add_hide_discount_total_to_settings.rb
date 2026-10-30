class AddHideDiscountTotalToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :hide_discount_total, :decimal
  end
end
