# frozen_string_literal: true

class AddPlusCheckoutOtpExtensionEnabledToSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :settings, :plus_checkout_otp_extension_enabled, :boolean, default: false, null: false
  end
end
