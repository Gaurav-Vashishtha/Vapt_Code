# frozen_string_literal: true

class RtoOrder < ApplicationRecord
  belongs_to :shop_domain

  validates :order_id, presence: true

  scope :for_domain, ->(domain) { joins(:shop_domain).where(shop_domains: { shopify_domain: domain.to_s.downcase.strip }) }

  def self.normalize_phone(raw)
    s = raw.to_s
    # Keep digits only so "+91..." and "91..." normalize to same key.
    s = s.tr("^0-9", "")
    s = s.sub(/\A0+/, "")
    s.presence
  end

  def self.normalize_email(raw)
    s = raw.to_s.strip.downcase
    s.presence
  end
end

