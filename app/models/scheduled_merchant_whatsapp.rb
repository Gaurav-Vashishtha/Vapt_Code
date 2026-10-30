# frozen_string_literal: true

class ScheduledMerchantWhatsapp < ApplicationRecord
  belongs_to :merchant_whatsapp_rule

  STATUSES = %w[pending scheduled sent skipped failed].freeze

  scope :pending, -> { where(status: "pending") }
  scope :sent, -> { where(status: "sent") }

  def shop
    return @shop if defined?(@shop)
    @shop = shop_id ? Shop.find_by(id: shop_id) : nil
  end

  def uninstalled_shop
    return @uninstalled_shop if defined?(@uninstalled_shop)
    @uninstalled_shop = uninstalled_shop_id ? UninstalledShop.find_by(id: uninstalled_shop_id) : nil
  end
end
