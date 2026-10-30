# frozen_string_literal: true

module MetaEvents
  # Per-shop ingest token handed to the web pixel via webPixel settings. Deriving it
  # from the shop domain means a token scraped off one storefront can't be replayed
  # against another shop.
  module Token
    def self.for(shop)
      domain = shop.respond_to?(:shopify_domain) ? shop.shopify_domain.to_s : shop.to_s
      return "" if domain.blank? || secret.blank?

      OpenSSL::HMAC.hexdigest("SHA256", secret, domain.strip.downcase)
    end

    def self.valid?(shop, provided)
      expected = self.for(shop)
      return false if expected.blank? || provided.to_s.blank?

      ActiveSupport::SecurityUtils.secure_compare(provided.to_s, expected)
    end

    def self.secret
      ENV["WEB_PIXEL_SHARED_SECRET"].presence ||
        ENV["WEB_PIXEL_CHECKOUT_SECRET"].presence ||
        ENV["SHOPIFY_API_SECRET"].presence ||
        Rails.application.secret_key_base.to_s
    end
    private_class_method :secret
  end
end
