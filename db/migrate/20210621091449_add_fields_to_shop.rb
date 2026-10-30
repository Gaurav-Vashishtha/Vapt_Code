class AddFieldsToShop < ActiveRecord::Migration[6.0]
  def change
    add_column :shops, :country_code, :string
    add_column :shops, :money_format, :string
    add_column :shops, :currency, :string
  end
end
