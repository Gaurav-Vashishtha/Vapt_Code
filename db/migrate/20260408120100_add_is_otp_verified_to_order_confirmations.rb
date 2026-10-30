# frozen_string_literal: true

class AddIsOtpVerifiedToOrderConfirmations < ActiveRecord::Migration[7.2]
  def change
    add_column :order_confirmations, :is_otp_verified, :boolean, null: false, default: false
    add_index :order_confirmations, [:shop_id, :is_otp_verified, :created_at], name: "idx_oc_shop_otp_verified_created_at"
  end
end

