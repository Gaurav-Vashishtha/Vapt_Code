class AddOrderStatusUrlToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :order_status_url, :string
    add_column :order_confirmations, :order_number, :string
  end
end
