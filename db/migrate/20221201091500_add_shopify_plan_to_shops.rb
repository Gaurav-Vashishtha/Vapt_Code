class AddShopifyPlanToShops < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :shopify_plan, :string
  end
end
