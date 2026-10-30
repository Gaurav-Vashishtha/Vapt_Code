# frozen_string_literal: true

class ShopDomain < ApplicationRecord
  has_many :shop_installations, dependent: :destroy

  validates :shopify_domain, presence: true, uniqueness: true

  def self.find_or_create_by_domain!(domain)
    normalized = domain.to_s.strip.downcase
    raise ArgumentError, "shopify_domain is required" if normalized.blank?
    find_or_create_by!(shopify_domain: normalized)
  end
end

