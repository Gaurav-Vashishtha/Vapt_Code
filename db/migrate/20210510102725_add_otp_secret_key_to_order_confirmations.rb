class AddOtpSecretKeyToOrderConfirmations < ActiveRecord::Migration[6.0]
  def change
    add_column :order_confirmations, :otp_secret_key, :string
  end
end
