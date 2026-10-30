# frozen_string_literal: true

# Abandoned pre-order OTP carts can be turned into Shopify draft orders (per-shop flag on
# additional_settings). pre_order_otp_draft_orders keeps one row per cart session
# (shop_id + device_id) so the same cart never produces two drafts.
class CreatePreOrderOtpDraftOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :additional_settings, :pre_order_otp_draft_orders, :boolean, null: false, default: false

    create_table :pre_order_otp_draft_orders do |t|
      t.bigint :shop_id, null: false
      t.string :device_id, null: false
      t.bigint :pre_order_otp_id
      t.string :phone_digits
      t.string :draft_order_gid
      t.string :draft_order_name
      t.string :cart_fingerprint
      t.string :status, null: false, default: "pending"
      t.string :shopify_order_id
      t.text :last_error
      t.timestamps
    end

    add_index :pre_order_otp_draft_orders, %i[shop_id device_id], unique: true, name: "idx_otp_drafts_shop_device"
    add_index :pre_order_otp_draft_orders, %i[shop_id phone_digits status], name: "idx_otp_drafts_shop_phone_status"
  end
end
