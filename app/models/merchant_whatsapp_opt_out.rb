# frozen_string_literal: true

class MerchantWhatsappOptOut < ApplicationRecord
  def self.opted_out?(domain)
    return false if domain.blank?

    exists?(shopify_domain: domain)
  end

  def self.opt_out!(domain:, shop_id: nil, phone: nil, reason: "merchant_request")
    record = find_or_initialize_by(shopify_domain: domain)
    record.assign_attributes(shop_id: shop_id, phone: phone, reason: reason)
    record.save!
    record
  end
end
