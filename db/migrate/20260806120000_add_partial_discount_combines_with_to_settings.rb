class AddPartialDiscountCombinesWithToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :partial_discount_combines_with_order, :boolean, null: false, default: false
    add_column :settings, :partial_discount_combines_with_product, :boolean, null: false, default: false
    add_column :settings, :partial_discount_combines_with_shipping, :boolean, null: false, default: false
  end
end
