class AddDefaultToPre < ActiveRecord::Migration[6.0]
  def change
        change_column_default :settings, :pre_heading, from: nil, to: 'Login/Signup to Checkout'
        change_column_default :settings, :pre_sub_heading , from: nil, to: 'Confirm your mobile number to proceed to checkout'
        change_column_default :settings, :pre_send_button_label , from: nil, to: 'Send Code'
        change_column_default :settings, :pre_verify_button_label , from: nil, to: 'Verify Code'
        change_column_default :settings, :pre_invalid_otp_msg , from: nil, to: 'Invalid OTP'
        change_column_default :settings, :pre_success_message , from: nil, to: 'Phone number verified - Proceed to checkout'
  end
end
