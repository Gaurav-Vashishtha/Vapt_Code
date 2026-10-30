class PreColumnsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_heading, :string , deafult: 'Login/Signup to Checkout'
    add_column :settings, :pre_sub_heading, :string , deafult: 'Confirm your mobile number to proceed to checkout'
    add_column :settings, :pre_send_button_label, :string , deafult: 'Send Code'
    add_column :settings, :pre_verify_button_label, :string , deafult: 'Verify Code'
    add_column :settings, :pre_invalid_otp_msg, :string , deafult: 'Invalid OTP'
    add_column :settings, :pre_success_message, :string , deafult: 'Phone number verified - Proceed to checkout'
    Setting.where(pre_heading: nil).update_all(pre_heading: 'Login/Signup to Checkout')
    Setting.where(pre_sub_heading: nil).update_all(pre_sub_heading: 'Confirm your mobile number to proceed to checkout')
    Setting.where(pre_send_button_label: nil).update_all(pre_send_button_label: 'Send Code')
    Setting.where(pre_verify_button_label: nil).update_all(pre_verify_button_label: 'Verify Code')
    Setting.where(pre_invalid_otp_msg: nil).update_all(pre_invalid_otp_msg: 'Invalid OTP')
    Setting.where(pre_success_message: nil).update_all(pre_success_message: 'Phone number verified - Proceed to checkout')

  end
end



