# frozen_string_literal: true

class AddWhatsappBspCommissionToShopChargeOverrides < ActiveRecord::Migration[7.2]
  def change
    add_column :shop_charge_overrides, :whatsapp_bsp_commission_usd, :decimal, precision: 10, scale: 6, if_not_exists: true
  end
end
