class AddCodFeeToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :cod_fee, :decimal, default: 0.0
  end
end
