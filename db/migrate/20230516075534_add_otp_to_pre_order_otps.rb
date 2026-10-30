class AddOtpToPreOrderOtps < ActiveRecord::Migration[6.0]
  def change
    add_column :pre_order_otps, :otp, :string
    add_index :pre_order_otps, :ip_address
    add_index :pre_order_otps, :device_id
  end
end
