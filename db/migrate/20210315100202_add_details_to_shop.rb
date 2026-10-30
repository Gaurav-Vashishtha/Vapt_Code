class AddDetailsToShop < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :customer_email, :string
    add_column :shops, :owner_email, :string
    add_column :shops, :owner_name, :string
    add_column :shops, :primary_locale, :string
    add_column :shops, :owner_phone, :string
    add_column :shops, :country_name, :string
    add_column :shops, :owner_timezone, :string
    add_column :shops, :shop_owner, :string
  end
end
