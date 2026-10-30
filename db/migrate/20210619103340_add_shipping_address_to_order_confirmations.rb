class AddShippingAddressToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :shipping_address, :string
  end
end
