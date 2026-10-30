class AddPaymentLinkIdToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :payment_link_id, :string
  end
end
