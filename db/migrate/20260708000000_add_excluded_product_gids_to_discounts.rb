class AddExcludedProductGidsToDiscounts < ActiveRecord::Migration[7.2]
  def change
    add_column :discounts, :excluded_product_gids, :jsonb, default: [], null: false
  end
end
