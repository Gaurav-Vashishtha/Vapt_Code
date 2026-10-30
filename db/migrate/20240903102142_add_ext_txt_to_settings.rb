class AddExtTxtToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :otp_ext_heading, :string , default:'Verify OTP for faster delivery'
    add_column :settings, :otp_ext_enter_otp_sent_on, :string , default:'Please enter the OTP sent on'
    add_column :settings, :otp_ext_sending_otp, :string , default:'Sending OTP to your mobile number...'
    add_column :settings, :otp_ext_enter_otp, :string , default:'Enter OTP'
    add_column :settings, :otp_ext_resend_otp_in, :string , default:'Resend OTP in'
    add_column :settings, :otp_ext_resend_otp, :string , default:'Resend OTP'
    add_column :settings, :otp_ext_get_code_in_whatsapp, :string , default:'Get code on WhatsApp'
    add_column :settings, :otp_ext_verify_otp, :string , default:'Verify OTP'
    add_column :settings, :otp_ext_successful, :string , default:'OTP Verification Successful!'
    add_column :settings, :otp_ext_change, :string , default:'change'
    add_column :settings, :otp_ext_submit, :string , default:'submit'
  end
end
