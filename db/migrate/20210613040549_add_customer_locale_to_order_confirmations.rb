class AddCustomerLocaleToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :customer_locale, :string
  end
end
