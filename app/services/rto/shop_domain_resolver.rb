# frozen_string_literal: true

module Rto
  class ShopDomainResolver
    def self.resolve!(shopify_domain)
      ShopDomain.find_or_create_by_domain!(shopify_domain).tap do |sd|
        sd.update_column(:last_seen_at, Time.current) rescue nil
      end
    end

    def self.resolve_from_shop!(shop)
      raise ArgumentError, "shop is required" if shop.blank?
      resolve!(shop.shopify_domain)
    end
  end
end

