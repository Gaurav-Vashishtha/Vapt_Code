class AddOtpFallbackTextToSettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :otp_fallback_text, :text
  end
end
