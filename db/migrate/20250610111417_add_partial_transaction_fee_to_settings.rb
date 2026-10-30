class AddPartialTransactionFeeToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :partial_transaction_fee, :decimal, default:0.0
  end
end
