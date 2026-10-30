# frozen_string_literal: true

# Per-shop WhatsApp charge overrides set by the support team from /admin/shop_charge_overrides.
# PricingJobs::DynamicChargeJob multiplies the normal per-message WhatsApp price (plan tier or
# India V3 rate) by the multiplier of the message's category: 1.0 = no change, 0.5 = half
# price, 0 = free. NULL = no override for that category.
class CreateShopChargeOverrides < ActiveRecord::Migration[7.2]
  def change
    create_table :shop_charge_overrides, if_not_exists: true do |t|
      t.bigint :shop_id, null: false
      t.decimal :whatsapp_utility_multiplier, precision: 8, scale: 4
      t.decimal :whatsapp_marketing_multiplier, precision: 8, scale: 4
      t.string :note
      t.timestamps
    end
    add_index :shop_charge_overrides, :shop_id, unique: true, if_not_exists: true
  end
end
