class AddPersistedOtpToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :persisted_otp, :string
  end
end
