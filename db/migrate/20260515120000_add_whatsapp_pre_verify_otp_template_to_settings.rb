class AddWhatsappPreVerifyOtpTemplateToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :whatsapp_pre_verify_otp_template, :string
  end
end
