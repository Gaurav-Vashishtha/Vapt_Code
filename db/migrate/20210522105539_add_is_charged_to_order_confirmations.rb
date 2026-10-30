class AddIsChargedToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :is_charged, :boolean, default: false
  end
end
