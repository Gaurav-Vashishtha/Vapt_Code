class AddIndexToOrderConfirmation < ActiveRecord::Migration[6.0]
  def change
    add_index :order_confirmations, :order_id
    add_index :order_confirmations, :order_status_url
  end
end
