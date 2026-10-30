class AddShopCreatedDateToShop < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :shop_created_date, :string
  end
end
