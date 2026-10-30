class DropPreColumns < ActiveRecord::Migration[6.0]
  def change
    remove_column :settings, :pre_heading
    remove_column :settings, :pre_sub_heading
    remove_column :settings, :pre_send_button_label
    remove_column :settings, :pre_verify_button_label
    remove_column :settings, :pre_invalid_otp_msg
    remove_column :settings, :pre_success_message
  end
end