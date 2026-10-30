class AddIsPrepaidChargedToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :is_prepaid_charged, :boolean
  end
end
