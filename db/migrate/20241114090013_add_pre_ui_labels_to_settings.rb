class AddPreUiLabelsToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :pre_phone_placeholder, :string , default:'Phone'
    add_column :settings, :pre_invalid_phone, :string , default:'Please enter a valid 10-digit phone number.'
    add_column :settings, :pre_verify_mobile, :string , default:'Verify Mobile Number'
    add_column :settings, :pre_enter_code, :string , default:'Enter the code sent to'
    add_column :settings, :pre_retry_in, :string , default:'Didnt receive the Code? Retry in'
    add_column :settings, :pre_resend, :string , default:'Resend'
    add_column :settings, :pre_failed_to_verify, :string , default:'Failed to verify OTP. Please try again.'
    add_column :settings, :pre_verifying, :string , default:'Verifying'
    add_column :settings, :pre_too_many, :string , default:'Too many attemps. Please select other payment options.'
  end
end
