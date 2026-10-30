class AddPhonepeTransactionIdsToOrderConfirmation < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :phonepe_transaction_ids, :string, default:''
  end
end
