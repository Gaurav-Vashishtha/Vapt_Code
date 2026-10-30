class AddEnablePreOrderOtpToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :enable_pre_order_otp, :boolean , default:false
  end
end
