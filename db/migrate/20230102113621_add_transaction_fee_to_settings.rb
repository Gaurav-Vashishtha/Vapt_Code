class AddTransactionFeeToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :transaction_fee, :float, default: 1.0
  end
end
