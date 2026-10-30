class AddOriginalCostToPartialProductMappings < ActiveRecord::Migration[7.2]
  def change
    add_column :partial_product_mappings, :original_cost, :decimal, default:0.0
  end
end
