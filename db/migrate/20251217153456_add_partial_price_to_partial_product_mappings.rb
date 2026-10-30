class AddPartialPriceToPartialProductMappings < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_product_mappings, :partial_price, :decimal, default: 0.0
  end
end
