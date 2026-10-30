class AddCountryCodeToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :country_code, :string
    add_column :order_confirmations, :ver_type, :string
  end
end
