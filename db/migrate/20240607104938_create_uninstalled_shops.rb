class CreateUninstalledShops < ActiveRecord::Migration[6.0]
  def change
    create_table :uninstalled_shops do |t|
      t.integer :shop_id
      t.string :shop_domain
      t.string :email
      t.string :phone
      t.string :shopify_created_date
      t.string :owner_name
      t.string :order_count
      t.string :country
      t.timestamps
    end
  end
end
