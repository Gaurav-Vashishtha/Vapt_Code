class AddIsRetriedToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :is_retried, :boolean, default: false
  end
end
