class AddReceiptEmailSentToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :receipt_email_sent, :boolean, default: false
  end
end

