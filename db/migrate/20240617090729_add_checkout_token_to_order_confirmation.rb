class AddCheckoutTokenToOrderConfirmation < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :checkout_token, :string
    add_index :order_confirmations, :checkout_token
  end
end
