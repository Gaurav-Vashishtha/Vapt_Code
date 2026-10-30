class AddPreColumns < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_heading, :string ,  deafult: 'Login/Signup to Checkout'
    add_column :settings, :pre_sub_heading, :string , deafult: 'Confirm your mobile number to proceed to checkout'
    add_column :settings, :pre_send_button_label, :string , deafult: 'Send Code'
    add_column :settings, :pre_verify_button_label, :string , deafult: 'Verify Code'
    add_column :settings, :pre_invalid_otp_msg, :string , deafult: 'Invalid OTP'
    add_column :settings, :pre_success_message, :string , deafult: 'Phone number verified - Proceed to checkout'
  end
end
